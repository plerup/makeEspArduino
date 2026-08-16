#====================================================================================
# makeESPArduino
#
# A makefile for ESP8266 and ESP32 Arduino projects.
#
# License: LGPL 2.1
# General and full license information is available at:
#    https://github.com/plerup/makeEspArduino
#
# Copyright (c) 2016-2026 Peter Lerup. All rights reserved.
#
#====================================================================================

START_TIME := $(shell date +%s)
__THIS_FILE := $(abspath $(lastword $(MAKEFILE_LIST)))
__TOOLS_DIR := $(dir $(__THIS_FILE))tools
OS ?= $(shell uname -s)

# Include possible operating-system-specific settings
-include $(dir $(__THIS_FILE))/os/$(OS).mk

# Include possible global user settings
CONFIG_ROOT ?= $(if $(XDG_CONFIG_HOME),$(XDG_CONFIG_HOME),$(HOME)/.config)
-include $(CONFIG_ROOT)/makeEspArduino/config.mk

# Include possible project-specific settings
-include $(firstword $(PROJ_CONF) $(dir $(SKETCH))config.mk)

# Freeze the configuration makefiles before generated include files are read.
# GNU make restarts after remaking an included makefile, so using MAKEFILE_LIST
# directly as a prerequisite of arduino.mk can cause it to be regenerated twice.
ARDUINO_CONFIG_MAKEFILES := $(MAKEFILE_LIST)

# Build threads; by default, use all available CPU cores
BUILD_THREADS ?= $(shell nproc)
MAKEFLAGS += -j $(BUILD_THREADS)

# Build verbosity; silent by default
ifndef VERBOSE
  MAKEFLAGS += --silent
endif

# Utility functions
uc = $(shell printf '%s' '$(1)' | tr '[:lower:]' '[:upper:]')
lc = $(shell printf '%s' '$(1)' | tr '[:upper:]' '[:lower:]')
git_description = $(shell git -C $(1) describe --tags --always --dirty 2>/dev/null || echo Unknown)
time_string = $(shell date +$(1))
find_files = $(shell find $2 | awk '/.*\.($1)$$/')

# ESP chip family
CHIP ?= esp8266
UC_CHIP := $(call uc,$(CHIP))
IS_ESP32 := $(if $(filter-out esp32,$(CHIP)),,1)

# Python interpreter used by helper tools
PYTHON ?= python3

# Serial flashing parameters
# If no port is specified, use the first USB serial device reported by pyserial.
UPLOAD_PORT ?= $(shell $(PYTHON) -c 'import serial.tools.list_ports as p; print(next((x.device for x in p.comports() if x.vid is not None), ""))' 2>/dev/null)

# Monitor definitions
MONITOR_SPEED ?= 115200
MONITOR_PORT ?= $(UPLOAD_PORT)
MONITOR_PAR ?= --rts=0 --dtr=0
MONITOR_COM ?= $(PYTHON) $(__TOOLS_DIR)/miniterm.py --exit-char 3 $(MONITOR_PAR) $(MONITOR_PORT) $(MONITOR_SPEED)

# OTA parameters
OTA_ADDR ?=
OTA_HPORT ?=
OTA_PORT ?= $(if $(IS_ESP32),3232,8266)
OTA_PWD ?=
OTA_ARGS = --progress --ip="$(OTA_ADDR)" --port="$(OTA_PORT)"
ifneq ($(OTA_HPORT),)
  OTA_ARGS += --host_port="$(OTA_HPORT)"
endif
ifneq ($(OTA_PWD),)
  OTA_ARGS += --auth="$(OTA_PWD)"
endif

# HTTP update parameters
HTTP_ADDR ?=
HTTP_URI ?= /update
HTTP_PWD ?= user
HTTP_USR ?= password
HTTP_OPT ?= --progress-bar -o /dev/null

# Build output directory
BUILD_ROOT ?= /tmp/mkESP
BUILD_DIR ?= $(BUILD_ROOT)/$(MAIN_NAME)_$(BOARD)

# Filesystem and corresponding disk directories
FS_TYPE ?= littlefs
FS_TYPE_LC := $(call lc,$(FS_TYPE))
FS_TYPE_UC := $(call uc,$(FS_TYPE))
MK_FS_MATCH = mk$(FS_TYPE_LC)
FS_DIR ?= $(dir $(SKETCH))data
FS_DUMP_DIR ?= $(BUILD_DIR)/file_system

# Make the selected filesystem available to project code
BUILD_EXTRA_FLAGS += -DFS_$(FS_TYPE_UC)=1 -DFS_TYPE=\"$(FS_TYPE_LC)\"

# Optional ESP32 USB CDC serial output on boot override
ifneq ($(IS_ESP32),)
  ifneq ($(USB_CDC),)
    BUILD_EXTRA_FLAGS += -DARDUINO_USB_CDC_ON_BOOT=$(USB_CDC)
  endif
endif

# The default board must be known before resolving an installed platform with arduino-cli
BOARD ?= $(if $(IS_ESP32),esp32,generic)

# ESP Arduino directories
ifndef ESP_ROOT
  # For a Boards Manager installation, arduino-cli is the authority for both
  # the installed platform and all package-managed tool locations.
  ARDUINO_INSTALL := 1
  ARDUINO_CLI ?= $(shell command -v arduino-cli 2>/dev/null)
  ifeq ($(ARDUINO_CLI),)
    $(error arduino-cli is required when ESP_ROOT is not specified. Download from: https://arduino.github.io/arduino-cli/1.5/ )
  endif
  ARDUINO_FQBN ?= $(CHIP):$(CHIP):$(BOARD)
  ESP_ROOT := $(shell $(ARDUINO_CLI) board details -b '$(ARDUINO_FQBN)' --show-properties=expanded 2>/dev/null | sed -n 's/^runtime.platform.path=//p' | head -1)
  ifeq ($(ESP_ROOT),)
    $(error arduino-cli could not resolve installed platform $(ARDUINO_FQBN))
  endif

  # ARDUINO_ROOT is only used for sketchbook/library preferences, never for
  # discovering platform tools.
  ARDUINO_ROOT ?= $(HOME)/.arduino15
  ARDUINO_PREFS = $(wildcard $(ARDUINO_ROOT)/preferences.txt)
  ifeq ($(ARDUINO_PREFS),)
    ARDUINO_LIBS ?= $(ARDUINO_ROOT)/libraries $(HOME)/Arduino/libraries
  else
    ARDUINO_LIBS ?= $(shell grep -o "sketchbook.path=.*" $(ARDUINO_PREFS) 2>/dev/null | cut -f2- -d=)/libraries
  endif
  ESP_ARDUINO_VERSION := $(notdir $(ESP_ROOT))
else
  # Location defined; assume that it is a git clone
  ESP_ARDUINO_VERSION = $(call git_description,$(ESP_ROOT))
  MK_FS_PATH ?= $(lastword $(wildcard $(ESP_ROOT)/tools/$(MK_FS_MATCH)/$(MK_FS_MATCH)))
endif
ESP_ROOT := $(abspath $(ESP_ROOT))
ESP_LIBS = $(ESP_ROOT)/libraries
SDK_ROOT = $(ESP_ROOT)/tools/sdk
TOOLS_ROOT = $(ESP_ROOT)/tools

# Validate the selected ESP Arduino version
ifeq ($(wildcard $(ESP_ROOT)/cores/$(CHIP)),)
  $(error $(ESP_ROOT) is not a valid directory for $(CHIP))
endif

# For a git checkout the filesystem tool is local to the checkout. For a
# Boards Manager installation MK_FS_PATH is emitted by parse_arduino.pl from
# arduino-cli's resolved runtime.tools.* properties.
ifeq ($(ARDUINO_INSTALL),)
  ifeq ($(wildcard $(MK_FS_PATH)),)
    $(error Invalid file system: "$(FS_TYPE)")
  endif
endif

# Validate the selected board
BOARD_OP = perl $(__TOOLS_DIR)/board_op.pl $(ESP_ROOT)/boards.txt "$(CPU)"
ifeq ($(shell $(BOARD_OP) $(BOARD) check),)
  $(error Invalid board: $(BOARD))
endif

# ESPTOOL_FILE is emitted by parse_arduino.pl from platform properties.
MCU ?= $(CHIP)
ESPTOOL ?= $(ESPTOOL_FILE)
ifeq ($(IS_ESP32),)
  # ESP8266 tools.esptool.cmd is the bundled Python interpreter. Use a small
  # wrapper to load the esptool and pyserial packages installed beside upload.py.
  ESPTOOL_COM ?= $(ESPTOOL) -I $(__TOOLS_DIR)/esptool_wrap.py $(ESP_ROOT)/tools --baud=$(UPLOAD_SPEED) --port $(UPLOAD_PORT) --chip $(MCU)
else
  ESPTOOL_COM ?= $(ESPTOOL) --baud=$(UPLOAD_SPEED) --port $(UPLOAD_PORT) --chip $(MCU)
endif

# Detect whether the specified goal involves building
GOALS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),all)
BUILDING := $(if $(filter $(GOALS), monitor list_boards list_flash_defs list_lwip set_git_version install help tools_dir preproc info),,1)

# Sketch (main program) selection
ifeq ($(BUILDING),)
  SKETCH = /dev/null
endif
ifdef DEMO
  SKETCH := $(if $(IS_ESP32),$(ESP_LIBS)/WiFi/examples/WiFiScan/WiFiScan.ino,$(ESP_LIBS)/ESP8266WiFi/examples/WiFiScan/WiFiScan.ino)
else
  SKETCH ?= $(wildcard *.ino *.pde)
endif
SKETCH := $(realpath $(wildcard $(SKETCH)))
ifeq ($(SKETCH),)
  $(error No sketch specified or found. Use "DEMO=1" for testing)
endif
ifeq ($(wildcard $(SKETCH)),)
  $(error Sketch $(SKETCH) not found)
endif
SRC_GIT_VERSION := $(call git_description,$(dir $(SKETCH)))

# Main output files
SKETCH_NAME := $(basename $(notdir $(SKETCH)))
MAIN_NAME ?= $(SKETCH_NAME)
MAIN_EXE ?= $(BUILD_DIR)/$(MAIN_NAME).bin
FS_IMAGE ?= $(BUILD_DIR)/FS.bin

# Build file extensions
OBJ_EXT = .o
DEP_EXT = .d

# Special tool definitions
OTA_TOOL ?= $(PYTHON) $(TOOLS_ROOT)/espota.py
HTTP_TOOL ?= curl

# Core source files
CORE_DIR = $(ESP_ROOT)/cores/$(CHIP)
CORE_SRC := $(call find_files,S|c|cpp,$(CORE_DIR))
CORE_OBJ := $(patsubst %,$(BUILD_DIR)/%$(OBJ_EXT),$(notdir $(CORE_SRC)))
CORE_LIB = $(BUILD_DIR)/arduino.ar
USER_OBJ_LIB = $(BUILD_DIR)/user_obj.ar

# Find project-specific source files and include directories
_LIBS = $(LIBS)
ifdef EXPAND_LIBS
  _LIBS := $(call find_files,S|c|cpp,$(_LIBS))
endif
SRC_LIST = $(BUILD_DIR)/src_list.mk
FIND_SRC_CMD = $(__TOOLS_DIR)/find_src.pl
$(SRC_LIST): $(MAKEFILE_LIST) $(FIND_SRC_CMD) | $(BUILD_DIR)
	$(if $(BUILDING),echo "- Finding all involved files for the build ...",)
	perl $(FIND_SRC_CMD) "$(EXCLUDE_DIRS)" "$(EXCLUDE_INC)" $(SKETCH) "$(realpath $(CUSTOM_LIBS))" "$(_LIBS)" $(ESP_LIBS) $(ARDUINO_LIBS) >$(SRC_LIST)

ifneq ($(MAKECMDGOALS),clean)
-include $(SRC_LIST)
endif

ifeq ($(suffix $(SKETCH)),.ino)
  # Use a sketch copy with the correct C++ extension
  SKETCH_CPP = $(BUILD_DIR)/$(notdir $(SKETCH)).cpp
  USER_SRC := $(subst $(SKETCH),$(SKETCH_CPP),$(USER_SRC))
endif

USER_OBJ := $(patsubst %,$(BUILD_DIR)/%$(OBJ_EXT),$(notdir $(USER_SRC)))
USER_DIRS := $(sort $(dir $(USER_SRC)))

# ESP8266 flash layout and ESP32 partition scheme
ifeq ($(IS_ESP32),)
  FLASH_DEF ?= $(shell $(BOARD_OP) $(BOARD) first_flash)
else
  PARTITION_SCHEME ?=
endif

# Use the first LwIPVariant definition for the board as the default
LWIP_VARIANT ?= $(shell $(BOARD_OP) $(BOARD) first_lwip)

# Handle possible state changes, e.g. Make command-line parameters or changed Git versions
CMD_LINE ?= $(shell tr "\0" " " </proc/$$PPID/cmdline)
CMD_LINE := $(CMD_LINE)
IGNORE_STATE ?= $(if $(BUILDING),,1)
ifeq ($(IGNORE_STATE),)
  STATE_LOG := $(BUILD_DIR)/state.txt
  STATE_INF := $(strip $(foreach par,$(CMD_LINE),$(if $(findstring =,$(par)),$(par),))) \
               $(SRC_GIT_VERSION) $(ESP_ARDUINO_VERSION)
  # Ignore port and speed changes
  STATE_INF := $(patsubst UPLOAD_%,,$(STATE_INF))
  PREV_STATE_INF := $(if $(wildcard $(STATE_LOG)),$(shell cat $(STATE_LOG)),$(STATE_INF))
  ifneq ($(PREV_STATE_INF),$(STATE_INF))
    $(info * Build state has changed, doing a full rebuild *)
    $(shell rm -rf "$(BUILD_DIR)")
  endif
  STATE_SAVE := $(shell mkdir -p $(BUILD_DIR) ; echo '$(STATE_INF)' >$(STATE_LOG))
endif

# Extract the actual build commands from the Arduino description files
ARDUINO_MK = $(BUILD_DIR)/arduino.mk
OS_NAME ?= linux
ARDUINO_DESC := $(shell find -L $(ESP_ROOT) -maxdepth 1 -name "*.txt" | sort)

# Boards Manager installations must provide the complete resolved board/property
# set from arduino-cli, but keep property references unexpanded so makeEspArduino
# overrides (F_CPU, FLASH_MODE, etc.) can still propagate through the recipes.
# Git checkouts do not use this file.
ARDUINO_CLI_PROPERTIES :=
ifneq ($(ARDUINO_INSTALL),)
  ARDUINO_CLI_PROPERTIES := $(BUILD_DIR)/arduino-cli.properties

$(ARDUINO_CLI_PROPERTIES): | $(BUILD_DIR)
	$(if $(BUILDING),echo "- Resolving Arduino platform properties ...",)
	@tmp="$@.tmp"; rm -f "$$tmp"; \
	$(ARDUINO_CLI) board details -b '$(ARDUINO_FQBN)' --show-properties=unexpanded >"$$tmp" || { \
	  rm -f "$$tmp"; \
	  echo "* arduino-cli failed to resolve $(ARDUINO_FQBN)" >&2; \
	  exit 1; \
	}; \
	mv "$$tmp" "$@"
endif

$(ARDUINO_MK): $(ARDUINO_DESC) $(ARDUINO_CLI_PROPERTIES) $(ARDUINO_CONFIG_MAKEFILES) $(__TOOLS_DIR)/parse_arduino.pl | $(BUILD_DIR)
	$(if $(BUILDING),echo "- Parsing Arduino configuration files ...",)
	ARDUINO_CLI_PROPERTIES='$(ARDUINO_CLI_PROPERTIES)' MK_FS_MATCH='$(MK_FS_MATCH)' perl $(__TOOLS_DIR)/parse_arduino.pl '$(ESP_ROOT)' $(BOARD) '$(FLASH_DEF)' '$(PARTITION_SCHEME)' '$(OS_NAME)' '$(LWIP_VARIANT)' $(ARDUINO_EXTRA_DESC) $(ARDUINO_DESC) >$(ARDUINO_MK)

ifneq ($(MAKECMDGOALS),clean)
-include $(ARDUINO_MK)
endif

# Compilation directories and paths
INCLUDE_DIRS += $(CORE_DIR) $(ESP_ROOT)/variants/$(INCLUDE_VARIANT) $(BUILD_DIR)
C_INCLUDES := $(foreach dir,$(INCLUDE_DIRS) $(USER_INC_DIRS),-I$(dir))
VPATH += $(shell find $(CORE_DIR) -type d) $(USER_DIRS)

# Automatically generated build-information source file
# Makes the build date and Git descriptions at the time of the actual build
# available as string constants in the program
BUILD_INFO_H = $(BUILD_DIR)/buildinfo.h
BUILD_INFO_CPP = $(BUILD_DIR)/buildinfo.c++
BUILD_INFO_OBJ = $(BUILD_INFO_CPP)$(OBJ_EXT)
BUILD_DATE = $(call time_string,"%Y-%m-%d")
BUILD_TIME = $(call time_string,"%H:%M:%S")

$(BUILD_INFO_H): | $(BUILD_DIR)
	@echo "typedef struct { const char *date, *time, *src_version, *env_version; } _tBuildInfo; extern _tBuildInfo _BuildInfo;" >$@

# Use ccache if it is available and not explicitly disabled (USE_CCACHE=0)
USE_CCACHE ?= $(if $(shell which ccache 2>/dev/null),1,0)
ifeq ($(USE_CCACHE),1)
  C_COM_PREFIX = ccache
  CPP_COM_PREFIX = $(C_COM_PREFIX)
endif

# Generated header files
GEN_H_FILES += $(BUILD_INFO_H)

# Special handling needed for esp32 build_opt.h
ifneq ($(IS_ESP32),)
BUILD_OPT_NAME = build_opt.h
BUILD_OPT_SRC = $(firstword $(wildcard $(dir $(SKETCH))/$(BUILD_OPT_NAME) /dev/null))
BUILD_OPT_DST = $(BUILD_DIR)/$(BUILD_OPT_NAME)
GEN_H_FILES += $(BUILD_OPT_DST)
$(BUILD_OPT_DST): $(BUILD_OPT_SRC) | $(BUILD_DIR)
	cp $(BUILD_OPT_SRC) $(BUILD_OPT_DST)
	touch $(BUILD_DIR)/file_opts
endif

# Build output root directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Create a C++ file from the sketch
$(SKETCH_CPP): $(SKETCH)
	echo "#include <Arduino.h>" >$@
	cat $(abspath $<) >>$@

# Build rules for the different source file types
$(BUILD_DIR)/%.cpp$(OBJ_EXT): %.cpp $(ARDUINO_MK) | $(GEN_H_FILES)
	@echo  $(<F)
	$(CPP_COM) $(CPP_EXTRA) $($(<F)_CFLAGS) $(abspath $<) -o $@

$(BUILD_DIR)/%.c$(OBJ_EXT): %.c $(ARDUINO_MK) | $(GEN_H_FILES)
	@echo  $(<F)
	$(C_COM) $(C_EXTRA) $($(<F)_CFLAGS) $(abspath $<) -o $@

$(BUILD_DIR)/%.S$(OBJ_EXT): %.S $(ARDUINO_MK) | $(GEN_H_FILES)
	@echo  $(<F)
	$(S_COM) $(S_EXTRA) $(abspath $<) -o $@

$(CORE_LIB): $(CORE_OBJ)
	@echo Creating core archive
	rm -f $@
	$(CORE_LIB_COM) $^

$(USER_OBJ_LIB): $(USER_OBJ)
	@echo Creating object archive
	rm -f $@
	$(LIB_COM) $@ $^

# Possible user-specific additional Make rules
ifdef USER_RULES
include $(USER_RULES)
endif

# ESP8266 historically benefits from linking user objects through an archive.
# ESP32 follows the Arduino core and links user object files directly.
ifeq ($(IS_ESP32),)
  USER_OBJ_DEP = $(if $(NO_USER_OBJ_LIB),$(USER_OBJ),$(USER_OBJ_LIB))
else
  USER_OBJ_DEP = $(USER_OBJ)
endif

# Linking the executable
$(MAIN_EXE): $(CORE_LIB) $(USER_LIBS) $(USER_OBJ_DEP)
	@echo Linking $(MAIN_EXE)
	$(PRELINK)
	@echo "  Versions: $(SRC_GIT_VERSION), $(ESP_ARDUINO_VERSION)"
	@echo 	'#include <buildinfo.h>' >$(BUILD_INFO_CPP)
	@echo '_tBuildInfo _BuildInfo = {"$(BUILD_DATE)","$(BUILD_TIME)","$(SRC_GIT_VERSION)","$(ESP_ARDUINO_VERSION)"};' >>$(BUILD_INFO_CPP)
	$(CPP_COM) $(BUILD_INFO_CPP) -o $(BUILD_INFO_OBJ)
	$(LD_COM) $(LD_EXTRA)
	$(GEN_PART_COM)
	$(OBJCOPY)
	$(SIZE_COM) | perl $(__TOOLS_DIR)/mem_use.pl "$(MEM_FLASH)" "$(MEM_RAM)"
ifneq ($(LWIP_INFO),)
	@printf "LwIPVariant: $(LWIP_INFO)\n"
endif
ifneq ($(FLASH_INFO),)
	@printf "Flash layout: $(FLASH_INFO)\n\n"
endif
ifneq ($(PARTITION_INFO),)
	@printf "Partition scheme: $(PARTITION_INFO)\n\n"
endif
	@perl -e 'print "Build complete. Elapsed time: ", time()-$(START_TIME),  " seconds\n\n"'

# Flashing operations
CHECK_PORT := $(if $(UPLOAD_PORT),\
                   @echo === Using upload port: $(UPLOAD_PORT) @ $(UPLOAD_SPEED),\
                   @echo "*** Upload port not found or defined" && exit 1)
upload flash: all
	$(CHECK_PORT)
	$(UPLOAD_COM)

ota: all
ifeq ($(OTA_ADDR),)
	@echo == Error: Address of device must be specified via OTA_ADDR
	exit 1
endif
	$(OTA_PRE_COM)
	$(OTA_TOOL) $(OTA_ARGS) --file="$(MAIN_EXE)"

http: all
ifeq ($(HTTP_ADDR),)
	@echo == Error: Address of device must be specified via HTTP_ADDR
	exit 1
endif
	$(HTTP_TOOL) $(HTTP_OPT) -F image=@$(MAIN_EXE) --user $(HTTP_USR):$(HTTP_PWD) http://$(HTTP_ADDR)$(HTTP_URI)
	@echo "\n"

$(FS_IMAGE): prebuild $(ARDUINO_MK) $(shell find $(FS_DIR)/ 2>/dev/null)
	@if [ -z "$(FS_SIZE)" ]; then \
	  echo "== Error: No filesystem partition is available"; \
	  exit 1; \
	fi
	@echo Generating filesystem image: $(FS_IMAGE)
	$(MK_FS_COM)

fs: $(FS_IMAGE)

upload_fs flash_fs: $(FS_IMAGE)
	$(CHECK_PORT)
	@echo Flashing filesystem image to $(call dump_hex,$(FS_START)): $(FS_IMAGE)
	$(ESPTOOL_COM) $(ESPTOOL_RESET) $(ESPTOOL_WRITE_FLASH) $(FS_START) $(FS_IMAGE)

ota_fs: $(FS_IMAGE)
ifeq ($(OTA_ADDR),)
	@echo == Error: Address of device must be specified via OTA_ADDR
	exit 1
endif
	$(OTA_TOOL) $(OTA_ARGS) --spiffs --file="$(FS_IMAGE)"

run: flash
	$(MONITOR_COM)

monitor:
ifeq ($(MONITOR_PORT),)
	@echo "*** Monitor port not found or defined" && exit 1
endif
	$(MONITOR_COM)

FLASH_FILE ?= $(BUILD_DIR)/esp_flash.bin
DUMP_ADDR ?= 0

# ESP8266 cores use the traditional underscore command names. Current ESP32
# tool packages use esptool v5 with hyphenated command names.
ifeq ($(IS_ESP32),)
  DUMP_SIZE ?= $(shell perl -e 'shift =~ /(\d+)([MK])/ || die "Invalid memory size\n";$$n=$$1*1024;$$n*=1024 if $$2 eq "M";print $$n;' $(FLASH_DEF))
  ESPTOOL_READ_FLASH = read_flash
  ESPTOOL_WRITE_FLASH = write_flash
  ESPTOOL_ERASE_FLASH = erase_flash
  ESPTOOL_RESET = $(UPLOAD_RESET)
else
  DUMP_SIZE ?= ALL
  ESPTOOL_READ_FLASH = read-flash
  ESPTOOL_WRITE_FLASH = write-flash
  ESPTOOL_ERASE_FLASH = erase-flash
  # esptool v5 uses hyphenated reset-mode values.
  ESPTOOL_RESET = $(subst _,-,$(UPLOAD_RESET))
endif

# Format dump address/size for display. Numeric values are shown in hexadecimal;
# ALL remains unchanged.
dump_hex = $(shell perl -e '$$v=shift; if (uc($$v) eq "ALL") { print "ALL"; } elsif ($$v =~ /^0x/i) { printf "0x%X", hex($$v); } elsif ($$v =~ /^(\d+)([kKmM])?$$/) { $$n=$$1; $$n*=1024 if defined $$2 && lc($$2) eq "k"; $$n*=1024*1024 if defined $$2 && lc($$2) eq "m"; printf "0x%X", $$n; } else { print $$v; }' '$(1)')

dump_flash:
	$(CHECK_PORT)
	@echo Dumping flash memory from $(call dump_hex,$(DUMP_ADDR)), size $(call dump_hex,$(DUMP_SIZE)), to: $(FLASH_FILE)
	$(ESPTOOL_COM) $(ESPTOOL_READ_FLASH) $(DUMP_ADDR) $(DUMP_SIZE) $(FLASH_FILE)

dump_fs: prebuild
	$(CHECK_PORT)
	@if [ -z "$(FS_START)" ] || [ -z "$(FS_SIZE)" ]; then \
	  echo "== Error: No filesystem partition is available"; \
	  exit 1; \
	fi
	@echo Dumping filesystem from $(call dump_hex,$(FS_START)), size $(call dump_hex,$(FS_SIZE)), to: $(FS_DUMP_DIR)
	$(ESPTOOL_COM) $(ESPTOOL_READ_FLASH) $(FS_START) $(FS_SIZE) $(FS_IMAGE)
	rm -rf $(FS_DUMP_DIR)
	mkdir -p $(FS_DUMP_DIR)
	@echo
	@echo == Files ==
	$(EXTRACT_FS_COM)

restore_flash:
	$(CHECK_PORT)
	@echo Restoring flash memory to $(call dump_hex,$(DUMP_ADDR)) from file: $(FLASH_FILE)
	$(ESPTOOL_COM) $(ESPTOOL_RESET) $(ESPTOOL_WRITE_FLASH) $(DUMP_ADDR) $(FLASH_FILE)

erase_flash:
	$(CHECK_PORT)
	$(ESPTOOL_COM) $(ESPTOOL_ERASE_FLASH)

# Build a library instead of an executable
LIB_OUT_FILE ?= $(BUILD_DIR)/$(MAIN_NAME).a
.PHONY: lib
lib: $(LIB_OUT_FILE)
$(LIB_OUT_FILE): $(filter-out $(BUILD_DIR)/$(MAIN_NAME).cpp$(OBJ_EXT),$(USER_OBJ))
	@echo Building library $(LIB_OUT_FILE)
	rm -f $(LIB_OUT_FILE)
	$(LIB_COM) $(LIB_OUT_FILE) $^

# Miscellaneous operations
clean:
	@echo Removing all build files
	rm -rf "$(BUILD_DIR)" $(FILES_TO_CLEAN)

list_boards:
	$(BOARD_OP) $(BOARD) list_names

list_lib: $(SRC_LIST)
	perl -e 'foreach (@ARGV) {print "$$_\n"}' "===== Include directories =====" $(USER_INC_DIRS)  "===== Source files =====" $(USER_SRC)

list_flash_defs:
ifeq ($(IS_ESP32),)
	$(BOARD_OP) $(BOARD) list_flash
else
	@echo "FLASH_DEF is only used for ESP8266; use PARTITION_SCHEME for ESP32"
endif

list_lwip:
	$(BOARD_OP) $(BOARD) list_lwip

# Update the Git version of the ESP Arduino repository
set_git_version:
ifeq ($(REQ_GIT_VERSION),)
	@echo == Error: Version tag must be specified with REQ_GIT_VERSION
	exit 1
endif
	@echo == Setting $(ESP_ROOT) to $(REQ_GIT_VERSION) ...
	git -C $(ESP_ROOT) checkout -fq --recurse-submodules $(REQ_GIT_VERSION)
	git -C $(ESP_ROOT) clean -fdxq -f
	git -C $(ESP_ROOT) submodule update --init
	git -C $(ESP_ROOT) submodule foreach -q --recursive git clean -xfd
	cd $(ESP_ROOT)/tools; ./get.py -q

# Generate a Visual Studio Code configuration and launch VS Code
BIN_DIR = /usr/local/bin
_MAKE_COM = make -f $(__THIS_FILE) ESP_ROOT=$(ESP_ROOT)
ifeq ($(CHIP),esp32)
  _MAKE_COM += CHIP=esp32
	_SCRIPT = espmake32
else
  _SCRIPT = espmake
endif
vscode: $(ARDUINO_MK)
	perl $(__TOOLS_DIR)/vscode.pl -n $(MAIN_NAME) -m "$(_MAKE_COM)" -w "$(VS_CODE_DIR)" -i "$(VSCODE_INC_EXTRA)" -p "$(VSCODE_PROJ_NAME)" $(CPP_COM)

# Create a shortcut command for running this file
install:
	@echo Creating command \"$(_SCRIPT)\" in $(BIN_DIR)
	sudo sh -c 'echo $(_MAKE_COM) "\"\$$@\"" >$(BIN_DIR)/$(_SCRIPT)'
	sudo chmod +x $(BIN_DIR)/$(_SCRIPT)

# Return the tools directory path (intended for locating vscode.pl from other makefiles)
tools_dir:
	@echo $(__TOOLS_DIR)

# Show RAM usage per variable
ram_usage: $(MAIN_EXE)
	$(shell find $(TOOLS_ROOT) | grep 'gcc-nm') -Clrtd --size-sort $(BUILD_DIR)/$(MAIN_NAME).elf | grep -i ' [b] '

# Show RAM and flash usage per object file used in the build
OBJ_INFO_FORM ?= 0
OBJ_INFO_SORT ?= 1
obj_info: $(MAIN_EXE)
	perl $(__TOOLS_DIR)/obj_info.pl "$(shell find $(TOOLS_ROOT) | grep 'elf-size$$')" "$(OBJ_INFO_FORM)" "$(OBJ_INFO_SORT)" $(BUILD_DIR)/*.o

# Analyze a crash log
crash: $(MAIN_EXE)
	perl $(__TOOLS_DIR)/crash_tool.pl $(ESP_ROOT) $(BUILD_DIR)/$(MAIN_NAME).elf

# Run the compiler preprocessor to get the fully expanded source for a file
preproc:
ifeq ($(SRC_FILE),)
	$(error SRC_FILE must be defined)
endif
	$(CPP_COM) -E $(SRC_FILE)

# Main default rule: build the executable
.PHONY: all
all: $(BUILD_DIR) $(ARDUINO_MK) prebuild $(MAIN_EXE)

# Prebuild is currently mandatory only for ESP32
USE_PREBUILD ?= $(if $(IS_ESP32),1,)
prebuild:
ifneq ($(USE_PREBUILD),)
	$(PREBUILD)
endif

help: $(ARDUINO_MK)
	@echo
	@echo "Generic makefile for building Arduino esp8266 and esp32 projects"
	@echo "This file can either be used directly or included from another makefile"
	@echo ""
	@echo "The following targets are available:"
	@echo "  all                  (default) Build the project application"
	@echo "  clean                Remove all intermediate build files"
	@echo "  lib                  Build a library with all involved object files"
	@echo "  flash                Build and flash the project application"
	@echo "  flash_fs             Build and flash the file system (when applicable)"
	@echo "  ota                  Build and flash via OTA"
	@echo "                         Params: OTA_ADDR, OTA_HPORT, OTA_PORT and OTA_PWD"
	@echo "  ota_fs               Build and flash the file system via OTA"
	@echo "  http                 Build and flash via HTTP (curl)"
	@echo "                         Params: HTTP_ADDR, HTTP_URI, HTTP_PWD and HTTP_USR"
	@echo "  dump_flash           Dump flash memory to a binary file"
	@echo "                         Params: FLASH_FILE, DUMP_ADDR and DUMP_SIZE"
	@echo "                         Defaults: DUMP_ADDR=$(DUMP_ADDR), DUMP_SIZE=$(DUMP_SIZE)"
	@echo "  restore_flash        Restore flash memory from a binary dump file"
	@echo "                         Params: FLASH_FILE and DUMP_ADDR"
	@echo "  dump_fs              Dump and extract the filesystem from flash"
	@echo "                         Params: FS_DUMP_DIR"
	@echo "  erase_flash          Erase the whole flash (use with care!)"
	@echo "  list_lib             Show a list of used source files and include directories"
	@echo "  set_git_version      Set the ESP Arduino Git repository to the tag version"
	@echo "                         specified with REQ_GIT_VERSION"
	@echo "  install              Create the commands \"espmake\" and \"espmake32\""
	@echo "  vscode               Create config file for Visual Studio Code and launch"
	@echo "  ram_usage            Show global variables RAM usage"
	@echo "  obj_info             Show memory usage per object file"
	@echo "  monitor              Start serial monitor on the upload port"
	@echo "  run                  Build flash and start serial monitor"
	@echo "  crash                Analyze stack trace from a crash"
	@echo "  preproc              Run compiler preprocessor on source file"
	@echo "                         specified via SRC_FILE"
	@echo "  list_boards          Show list of boards from the Arduino core"
	@echo "  info                 Show the location and version of the selected ESP Arduino core"
	@echo "Configurable parameters:"
	@echo "  SKETCH               Main source file"
	@echo "                         If not specified the first sketch in current"
	@echo "                         directory will be used."
	@echo "  LIBS                 Use this variable to declare additional directories"
	@echo "                         and/or files which should be included in the build"
	@echo "  CHIP                 Set to esp8266 or esp32. Default: '$(CHIP)'"
	@echo "  BOARD                Name of the target board. Default: '$(BOARD)'"
	@echo "                         Use 'list_boards' to get list of available ones"
ifeq ($(IS_ESP32),)
	@echo "  FLASH_DEF            ESP8266 flash layout. Default: '$(FLASH_DEF)'"
	@echo "                         Use 'list_flash_defs' to show available layouts"
else
	@echo "  PARTITION_SCHEME     ESP32 partition scheme"
	@echo "                         Empty means use the board/core default"
endif
	@echo "  BUILD_DIR            Directory for intermediate build files."
	@echo "                         Default '$(BUILD_DIR)'"
	@echo "  BUILD_EXTRA_FLAGS    Additional parameters for the compilation commands"
ifeq ($(IS_ESP32),1)
	@echo "  USB_CDC              Enable USB CDC serial output on boot (0 or 1)"
	@echo "                         Default: board/core configuration"
endif
	@echo "  COMP_WARNINGS        Compilation warning options. Default: $(COMP_WARNINGS)"
	@echo "  FS_TYPE              Filesystem type. Default: $(FS_TYPE)"
	@echo "  FS_DIR               Filesystem root directory"
	@echo "  FS_DUMP_DIR          Directory used by dump_fs"
	@echo "                         Default: $(FS_DUMP_DIR)"
	@echo "  UPLOAD_PORT          Serial flashing port name. Default: '$(UPLOAD_PORT)'"
	@echo "  UPLOAD_SPEED         Serial flashing baud rate. Default: '$(UPLOAD_SPEED)'"
	@echo "  MONITOR_SPEED        Baud rate for the monitor. Default: '$(MONITOR_SPEED)'"
	@echo "  FLASH_FILE           Binary file for dump and restore flash operations"
	@echo "                         Default: '$(FLASH_FILE)'"
	@echo "  DUMP_ADDR            Start address for dump and restore"
	@echo "                         Default: $(DUMP_ADDR)"
	@echo "  DUMP_SIZE            Dump size in bytes, hex, k/M suffix, or ALL"
	@echo "                         Default: $(DUMP_SIZE)"
	@echo "  LWIP_VARIANT         Use specified variant of the lwip library when applicable"
	@echo "                         Use 'list_lwip' to get list of available ones"
	@echo "                         Default: $(LWIP_VARIANT) ($(LWIP_INFO))"
	@echo "  VERBOSE              Set to 1 to get full printout of the build"
	@echo "  BUILD_THREADS        Number of parallel build threads"
	@echo "                         Default: Maximum possible, based on number of CPUs"
	@echo "  USE_CCACHE           Set to 0 to disable ccache when it is available"
ifeq ($(IS_ESP32),)
	@echo "  NO_USER_OBJ_LIB      Set to 1 to link ESP8266 user objects directly"
endif
	@echo

# Show installation information
info:
	echo == Build info
	echo "  CHIP:        $(CHIP)"
	echo "  MCU:         $(MCU)"
	echo "  ESP_ROOT:    $(ESP_ROOT)"
	echo "  Version:     $(ESP_ARDUINO_VERSION)"
	echo "  Threads:     $(BUILD_THREADS)"
	echo "  Upload port: $(UPLOAD_PORT)"

# Include all available dependencies from the previous compilation
-include $(wildcard $(BUILD_DIR)/*$(DEP_EXT))

DEFAULT_GOAL ?= all
.DEFAULT_GOAL := $(DEFAULT_GOAL)

