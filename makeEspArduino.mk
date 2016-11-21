#====================================================================================
# makeESPArduino
#
# A makefile for ESP8286 Arduino projects.
# Edit the contents of this file to suit your project
# or just include it and override the applicable macros.
#
# License: GPL 2.1
# General and full license information is available at:
#    https://github.com/plerup/makeEspArduino
#
# Copyright (c) 2016 Peter Lerup. All rights reserved.
#
#====================================================================================

#====================================================================================
# Project specfic values
#====================================================================================

# Include possible project makefile. This can be used to override the defaults below
-include $(firstword $(PROJ_CONF) $(dir $(SKETCH))config.mk)

#=== Default values

# Main source file (sketch).
# If this variable is not specified the first sketch in current directory will be used.
# If none is found there, a demo example will be used instead.
SKETCH ?=

# Includes in the sketch file of libraries from within the ESP8266 Arduino directories can be automatically
# detected but if this is not enough, define this variable with all libraries or directories needed.
LIBS ?=

# Board specific definitions
BOARD ?= generic
F_CPU ?= 80000000L
FLASH_DEF ?= 4M3M
FLASH_MODE ?= dio
FLASH_SPEED ?= 40

# Upload parameters
UPLOAD_PORT ?= /dev/ttyUSB0
UPLOAD_VERB ?= -v

# OTA parameters
ESP_ADDR ?= ESP_123456
ESP_PORT ?= 8266
ESP_PWD ?= 123

# HTTP update parameters
HTTP_ADDR ?= ESP_123456
HTTP_URI ?= /update
HTTP_PWD ?= user
HTTP_USR ?= password

# Output directory
BUILD_DIR ?= /tmp/mkESP/$(MAIN_NAME)_$(BOARD)

# File system source directory
FS_DIR ?= $(dir $(SKETCH))data

# Which include files to use from $(ESP_ROOT)/variants/
INCLUDE_VARIANT ?= generic

#====================================================================================
# Standard build logic and values
#====================================================================================

START_TIME := $(shell perl -e "print time();")

# ESP8266 Arduino directories
ifndef ESP_ROOT
  # Location not defined, find and use the version in the Arduino IDE installation
  OS ?= $(shell uname -s)
  ifeq ($(OS), Windows_NT)
    ARDUINO_DIR = $(shell cygpath -m $(LOCALAPPDATA)/Arduino15/packages/esp8266)
  else ifeq ($(OS), Darwin)
    ARDUINO_DIR = $(HOME)/Library/Arduino15/packages/esp8266
  else
    ARDUINO_DIR = $(HOME)/.arduino15/packages/esp8266
  endif
  ESP_ROOT := $(lastword $(wildcard $(ARDUINO_DIR)/hardware/esp8266/*))
  ifeq ($(ESP_ROOT),)
    $(error No installed version of ESP8266 Arduino found)
  endif
  ESP_ARDUINO_VERSION := $(notdir $(ESP_ROOT))
  # Find used version of compiler and tools
  COMP_PATH := $(lastword $(wildcard $(ARDUINO_DIR)/tools/xtensa-lx106-elf-gcc/*))
  ESPTOOL_PATH := $(lastword $(wildcard $(ARDUINO_DIR)/tools/esptool/*))
  MKSPIFFS_PATH := $(lastword $(wildcard $(ARDUINO_DIR)/tools/mkspiffs/*))
else
  # Location defined, assume it is git clone
  ESP_ARDUINO_VERSION = $(call git_description,$(ESP_ROOT))
endif
ESP_LIBS = $(ESP_ROOT)/libraries
SDK_ROOT = $(ESP_ROOT)/tools/sdk
TOOLS_ROOT = $(ESP_ROOT)/tools

# Search for sketch if not defined
SKETCH := $(realpath $(firstword  $(SKETCH) \
                         $(wildcard *.ino) \
                         $(ESP_LIBS)/ESP8266WebServer/examples/HelloServer/HelloServer.ino \
                       ) \
            )
ifeq ($(wildcard $(SKETCH)),)
  $(error Sketch $(SKETCH) not found)
endif
# Main output definitions
MAIN_NAME := $(basename $(notdir $(SKETCH)))
MAIN_EXE = $(BUILD_DIR)/$(MAIN_NAME).bin
FS_IMAGE = $(BUILD_DIR)/FS.spiffs

ifeq ($(OS), Windows_NT)
  # Adjust critical paths
  BUILD_DIR := $(shell cygpath -m $(BUILD_DIR))
  SKETCH := $(shell cygpath -m $(SKETCH))
endif

# Build file extensions
OBJ_EXT = .o
DEP_EXT = .d

# Special tool definitions
OTA_TOOL = $(TOOLS_ROOT)/espota.py
HTTP_TOOL = curl

# Core source files
CORE_DIR = $(ESP_ROOT)/cores/esp8266
CORE_SRC := $(shell find $(CORE_DIR) -name "*.S" -o -name "*.c" -o -name "*.cpp")
CORE_OBJ := $(patsubst %,$(BUILD_DIR)/%$(OBJ_EXT),$(notdir $(CORE_SRC)))
CORE_LIB = $(BUILD_DIR)/arduino.ar

# User defined compilation units and directories
ifeq ($(LIBS),)
  # Automatically find directories with header files used by the sketch
  LIBS := $(shell perl -e 'use File::Find;$$d = shift;while (<>) {$$f{"$$1"} = 1 if /^\s*\#include\s+[<"]([^>"]+)/;}find(sub {print $$File::Find::dir," " if $$f{$$_}}, $$d);'  $(ESP_LIBS) $(SKETCH))
  ifeq ($(LIBS),)
    # No dependencies found
    LIBS = /dev/null
  endif
endif

SKETCH_DIR = $(dir $(SKETCH))
USER_INC := $(shell find $(SKETCH_DIR) $(LIBS) -name "*.h")
USER_SRC := $(SKETCH) $(shell find $(SKETCH_DIR) $(LIBS) -name "*.S" -o -name "*.c" -o -name "*.cpp")
# Object file suffix seems to be significant for the linker...
USER_OBJ := $(subst .ino,.cpp,$(patsubst %,$(BUILD_DIR)/%$(OBJ_EXT),$(notdir $(USER_SRC))))
USER_DIRS := $(sort $(dir $(USER_SRC)))
USER_INC_DIRS := $(sort $(dir $(USER_INC)))

# Compilation directories and path
INCLUDE_DIRS += $(CORE_DIR) $(ESP_ROOT)/variants/$(INCLUDE_VARIANT) $(BUILD_DIR)
C_INCLUDES := $(foreach dir,$(INCLUDE_DIRS) $(USER_INC_DIRS),-I$(dir))
VPATH += $(shell find $(CORE_DIR) -type d) $(USER_DIRS)

# Automatically generated build information data
# Makes the build date and git descriptions at the actual build event available as string constants in the program
BUILD_INFO_H = $(BUILD_DIR)/buildinfo.h
BUILD_INFO_CPP = $(BUILD_DIR)/buildinfo.c++
BUILD_INFO_OBJ = $(BUILD_INFO_CPP)$(OBJ_EXT)

$(BUILD_INFO_H): | $(BUILD_DIR)
	echo "typedef struct { const char *date, *time, *src_version, *env_version;} _tBuildInfo; extern _tBuildInfo _BuildInfo;" >$@

# Utility functions
git_description = $(shell git -C  $(1) describe --tags --always --dirty 2>/dev/null || echo Unknown)
time_string = $(shell date +$(1))

# The actual build commands are to be extracted from the Arduino description files
ARDUINO_MK = $(BUILD_DIR)/arduino.mk
ARDUINO_DESC := $(shell find $(ESP_ROOT) -maxdepth 1 -name "*.txt")
$(ARDUINO_MK): $(ARDUINO_DESC) $(MAKEFILE_LIST) | $(BUILD_DIR)
	perl -e "$$PARSE_ARDUINO" $(BOARD) $(FLASH_DEF) $(ARDUINO_DESC) >$(ARDUINO_MK)

-include $(ARDUINO_MK)

# Build rules
$(BUILD_DIR)/%.cpp$(OBJ_EXT): %.cpp $(BUILD_INFO_H) $(ARDUINO_MK)
	echo  $(<F)
	$(CPP_COM) $(CPP_EXTRA) $< -o $@

$(BUILD_DIR)/%.cpp$(OBJ_EXT): %.ino $(BUILD_INFO_H) $(ARDUINO_MK)
	echo  $(<F)
	$(CPP_COM) $(CPP_EXTRA) -x c++ -include $(CORE_DIR)/Arduino.h $< -o $@

$(BUILD_DIR)/%.c$(OBJ_EXT): %.c $(ARDUINO_MK)
	echo  $(<F)
	$(C_COM) $(C_EXTRA) $< -o $@

$(BUILD_DIR)/%.S$(OBJ_EXT): %.S $(ARDUINO_MK)
	echo  $(<F)
	$(S_COM) $(S_EXTRA) $< -o $@

$(CORE_LIB): $(CORE_OBJ)
	echo  Creating core archive
	rm -f $@
	$(AR_COM) $^

BUILD_DATE = $(call time_string,"%Y-%m-%d")
BUILD_TIME = $(call time_string,"%H:%M:%S")
SRC_GIT_VERSION := $(call git_description,$(dir $(SKETCH)))

$(MAIN_EXE): $(CORE_LIB) $(USER_OBJ)
	echo Linking $(MAIN_EXE)
	echo "  Versions: $(SRC_GIT_VERSION), $(ESP_ARDUINO_VERSION)"
	echo 	'#include <buildinfo.h>' >$(BUILD_INFO_CPP)
	echo '_tBuildInfo _BuildInfo = {"$(BUILD_DATE)","$(BUILD_TIME)","$(SRC_GIT_VERSION)","$(ESP_ARDUINO_VERSION)"};' >>$(BUILD_INFO_CPP)
	$(CPP_COM) $(BUILD_INFO_CPP) -o $(BUILD_INFO_OBJ)
	$(LD_COM)
	$(ELF2BIN_COM)
	$(SIZE_COM) | perl -e "$$MEM_USAGE"
	perl -e 'print "Build complete. Elapsed time: ", time()-$(START_TIME),  " seconds\n\n"'

upload flash: all
	$(UPLOAD_COM)

ota: all
	$(OTA_TOOL) -i $(ESP_ADDR) -p $(ESP_PORT) -a $(ESP_PWD) -f $(MAIN_EXE)

http: all
	$(HTTP_TOOL) --verbose -F image=@$(MAIN_EXE) --user $(HTTP_USR):$(HTTP_PWD) http://$(HTTP_ADDR)$(HTTP_URI)
	echo "\n"

$(FS_IMAGE): $(wildcard $(FS_DIR)/*)
	echo Generating filesystem image...
	$(MKSPIFFS_COM)

fs: $(FS_IMAGE)

upload_fs: $(FS_IMAGE)
	$(FS_UPLOAD_COM)

clean:
	echo Removing all build files...
	rm  -rf $(BUILD_DIR)/*

list_lib:
	echo === User specific libraries ===
	perl -e 'foreach (@ARGV) {print "$$_\n"}' "* Include directories:" $(USER_INC_DIRS)  "* Library source files:" $(USER_SRC)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: all
all: $(BUILD_DIR) $(ARDUINO_MK) $(BUILD_INFO_H) prebuild $(MAIN_EXE)

prebuild:
ifdef USE_PREBUILD
	$(PREBUILD_COM)
endif

# Include all available dependencies
-include $(wildcard $(BUILD_DIR)/*$(DEP_EXT))

.DEFAULT_GOAL = all

ifndef SINGLE_THREAD
  # Use multithreaded builds by default
  MAKEFLAGS += -j
endif

ifndef VERBOSE
  # Set silent mode as default
  MAKEFLAGS += --silent
endif

# Inline Perl scripts

# Parse Arduino build commands from the descriptions
define PARSE_ARDUINO
my $$board = shift;
my $$flashSize = shift;
my %v;

$$v{'runtime.platform.path'} = '$$(ESP_ROOT)';
$$v{'includes'} = '$$(C_INCLUDES)';
$$v{'runtime.ide.version'} = '10605';
$$v{'build.arch'} = 'ESP8266';
$$v{'build.project_name'} = '$$(MAIN_NAME)';
$$v{'build.path'} = '$$(BUILD_DIR)';
$$v{'build.flash_freq'} = '$$(FLASH_SPEED)';
$$v{'object_files'} = '$$^ $$(BUILD_INFO_OBJ)';
$$v{'runtime.tools.xtensa-lx106-elf-gcc.path'} = '$$(COMP_PATH)';
$$v{'runtime.tools.esptool.path'} = '$$(ESPTOOL_PATH)';
$$v{'runtime.tools.mkspiffs.path'} = '$$(MKSPIFFS_PATH)';

foreach my $$fn (@ARGV) {
   open($$f, $$fn) || die "Failed to open: $$fn\n";
   while (<$$f>) {
      next unless /(\w[\w\-\.]+)=(.*)/;
      my ($$key, $$val) =($$1, $$2);
		$$board_defined = 1 if $$key eq "$$board.name";
      $$key =~ s/$$board\.menu\.FlashSize\.$$flashSize\.//;
		$$key =~ s/^$$board\.//;
      $$key =~ s/^tools\.esptool\.//;
      $$v{$$key} = $$val;
   }
   close($$f);
}
die "* Uknown board $$board\n" unless $$board_defined;
$$v{'build.flash_mode'} = '$$(FLASH_MODE)';
$$v{'build.f_cpu'} = '$$(F_CPU)';
$$v{'upload.verbose'} = '$$(UPLOAD_VERB)';
print "UPLOAD_RESET ?= $$v{'upload.resetmethod'}\n";
$$v{'upload.resetmethod'} = '$$(UPLOAD_RESET)';
print "UPLOAD_SPEED ?= $$v{'upload.speed'}\n";
$$v{'upload.speed'} = '$$(UPLOAD_SPEED)';
$$v{'serial.port'} = '$$(UPLOAD_PORT)';

foreach my $$key (sort keys %v) {
   while ($$v{$$key} =~/\{/) {
      $$v{$$key} =~ s/\{([\w\-\.]+)\}/$$v{$$1}/;
      $$v{$$key} =~ s/""//;
   }
   $$v{$$key} =~ s/ -o $$//;
   $$v{$$key} =~ s/(-D\w+=)"([^"]+)"/$$1\\"$$2\\"/g;
}

print "C_COM=$$v{'recipe.c.o.pattern'}\n";
print "CPP_COM=$$v{'recipe.cpp.o.pattern'}\n";
print "S_COM=$$v{'recipe.S.o.pattern'}\n";
print "AR_COM=$$v{'recipe.ar.pattern'}\n";
print "LD_COM=$$v{'recipe.c.combine.pattern'}\n";
print "ELF2BIN_COM=$$v{'recipe.objcopy.hex.pattern'}\n";
print "SIZE_COM=$$v{'recipe.size.pattern'}\n";
my $$flash_size = sprintf("0x%X", hex($$v{'build.spiffs_end'})-hex($$v{'build.spiffs_start'}));
print "MKSPIFFS_COM=$$v{'tools.mkspiffs.path'}/$$v{'tools.mkspiffs.cmd'} -b $$v{'build.spiffs_blocksize'} -s $$flash_size -c \$$(FS_DIR) \$$(FS_IMAGE)\n";
print "UPLOAD_COM=$$v{'upload.pattern'}\n";
my $$fs_upload_com = $$v{'upload.pattern'};
$$fs_upload_com =~ s/(.+ -ca) .+/$$1 $$v{'build.spiffs_start'} -cf \$$(FS_IMAGE)/;
print "FS_UPLOAD_COM=$$fs_upload_com\n";
my $$val = $$v{'recipe.hooks.core.prebuild.1.pattern'};
$$val =~ s/bash -c "(.+)"/$$1/;
$$val =~ s/(#define .+0x)(\`)/"\\$$1\"$$2/;
$$val =~ s/(\\)//;
print "PREBUILD_COM=$$val\n";
endef
export PARSE_ARDUINO

# Convert memory information
define MEM_USAGE
while (<>) {
  $$r += $$1 if /^\.(?:data|rodata|bss)\s+(\d+)/;
  $$f += $$1 if /^\.(?:irom0\.text|text|data|rodata)\s+(\d+)/;
}
print "\nMemory usage\n";
print sprintf("  %-6s %6d bytes\n" x 2 ."\n", "Ram:", $$r, "Flash:", $$f);
endef
export MEM_USAGE
