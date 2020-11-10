#!/usr/bin/env perl
#====================================================================================
# parse_arduino.pl
#
# Parses Arduino configuration files and writes the content
# of a corresponding makefile
#
# This file is part of makeESPArduino
# License: LGPL 2.1
# General and full license information is available at:
#    https://github.com/plerup/makeEspArduino
#
# Copyright (c) 2016-2020 Peter Lerup. All rights reserved.
#
#====================================================================================

use strict;

my $chip = shift;
my $board = shift;
my $flashSize = shift;
my $os = shift;
$os =~ s/Windows_NT/windows/;
$os =~ s/Linux/linux/;
$os =~ s/Darwin/macosx/;
my $lwipvariant = shift;
my %vars;

sub def_var {
  my ($name, $var) = @_;
  print "$var ?= $vars{$name}\n";
  $vars{$name} = "\$($var)";
}

# Some defaults
$vars{'runtime.platform.path'} = '$(ESP_ROOT)';
$vars{'includes'} = '$(C_INCLUDES)';
$vars{'runtime.ide.version'} = '10605';
$vars{'build.arch'} = uc("$chip");
$vars{'build.project_name'} = '$(MAIN_NAME)';
$vars{'build.path'} = '$(BUILD_DIR)';
$vars{'object_files'} = '$^ $(BUILD_INFO_OBJ)';
$vars{'archive_file_path'} = '$(CORE_LIB)';

# Parse the files and define the corresponsing variables
my $board_defined;
foreach my $fn (@ARGV) {
  my $f;
  open($f, $fn) || die "Failed to open: $fn\n";
  while (<$f>) {
    s/\s+$//;
    s/\.esptool_py\./.esptool./g;
    next unless /^(\w[\w\-\.]+)=(.*)/;
    my ($key, $val) =($1, $2);
    $board_defined = 1 if $key eq "$board.name";
    # Truncation of some variable names is needed
    $key =~ s/$board\.menu\.(?:FlashSize|eesz)\.$flashSize\.//;
    $key =~ s/$board\.menu\.CpuFrequency\.[^\.]+\.//;
    $key =~ s/$board\.menu\.(?:FlashFreq|xtal)\.[^\.]+\.//;
    $key =~ s/$board\.menu\.UploadSpeed\.[^\.]+\.//;
    $key =~ s/$board\.menu\.baud\.[^\.]+\.//;
    $key =~ s/$board\.menu\.ResetMethod\.[^\.]+\.//;
    $key =~ s/$board\.menu\.FlashMode\.[^\.]+\.//;
    $key =~ s/$board\.menu\.(?:LwIPVariant|ip)\.$lwipvariant\.//;
    $key =~ s/^$board\.//;
    $vars{$key} ||= $val;
    $vars{$1} = $vars{$key} if $key =~ /(.+)\.$os$/;
  }
  close($f);
}
# Some additional defaults may be needed
$vars{'runtime.tools.xtensa-lx106-elf-gcc.path'} ||= '$(COMP_PATH)';
$vars{'runtime.tools.xtensa-esp32-elf-gcc.path'} ||= '$(COMP_PATH)';
$vars{'runtime.tools.esptool.path'} ||= '$(ESPTOOL_PATH)';
$vars{'runtime.tools.python.path'} = '$(PYTHON_PATH)';
$vars{'runtime.tools.python3.path'} = '$(PYTHON3_PATH)';

die "* Unknown board $board\n" unless $board_defined;
print "# Board definitions\n";
def_var('build.code_debug', 'CORE_DEBUG_LEVEL');
def_var('build.f_cpu', 'F_CPU');
def_var('build.flash_mode', 'FLASH_MODE');
def_var('build.flash_freq', 'FLASH_SPEED');
def_var('upload.resetmethod', 'UPLOAD_RESET');
def_var('upload.speed', 'UPLOAD_SPEED');
def_var('compiler.warning_flags', 'COMP_WARNINGS');
$vars{'serial.port'} = '$(UPLOAD_PORT)';
$vars{'recipe.objcopy.hex.pattern'} =~ s/[^"]+\/bootloaders\/eboot\/eboot.elf/\$(BOOT_LOADER)/;
$vars{'recipe.objcopy.hex.1.pattern'} =~ s/[^"]+\/bootloaders\/eboot\/eboot.elf/\$(BOOT_LOADER)/;
$vars{'recipe.hooks.linking.prelink.1.pattern'} =~ s/\{build.vtable_flags\}/\$(VTABLE_FLAGS)/;
$vars{'tools.esptool.upload.pattern'} =~ s/\{(cmd|path)\}/\{tools.esptool.$1\}/g;
$vars{'compiler.cpreprocessor.flags'} .= " \$(C_PRE_PROC_FLAGS)";
$vars{'build.extra_flags'} .= " \$(BUILD_EXTRA_FLAGS)";

# Some additional replacements
foreach my $key (sort keys %vars) {
   while ($vars{$key} =~/\{/) {
      $vars{$key} =~ s/\{([\w\-\.]+)\}/$vars{$1}/;
      $vars{$key} =~ s/""//;
   }
   $vars{$key} =~ s/ -o\s+$//;
   $vars{$key} =~ s/(-D\w+=)"([^"]+)"/$1\\"$2\\"/g;
}

# Print the makefile content
print "INCLUDE_VARIANT = $vars{'build.variant'}\n";
print "# Commands\n";
print "C_COM=\$(C_COM_PREFIX) $vars{'recipe.c.o.pattern'}\n";
print "CPP_COM=\$(CPP_COM_PREFIX) $vars{'recipe.cpp.o.pattern'}\n";
print "S_COM=$vars{'recipe.S.o.pattern'}\n";
print "LIB_COM=\"$vars{'compiler.path'}$vars{'compiler.ar.cmd'}\"\n";
print "CORE_LIB_COM=$vars{'recipe.ar.pattern'}\n";
print "LD_COM=$vars{'recipe.c.combine.pattern'}\n";
print "PART_FILE?=\$(ESP_ROOT)/tools/partitions/default.csv\n";
my $gen_part_com = $vars{'recipe.objcopy.eep.pattern'} || $vars{'recipe.objcopy.partitions.bin.pattern'};
$gen_part_com =~ s/\"([^\"]+\.csv)\"/\$(PART_FILE)/;
print "GEN_PART_COM=$gen_part_com\n";
print "ELF2BIN_COM=", $vars{'recipe.objcopy.hex.pattern'} || $vars{'recipe.objcopy.hex.1.pattern'} || $vars{'recipe.objcopy.bin.pattern'}, "\n";
print "SIZE_COM=$vars{'recipe.size.pattern'}\n";
if ($vars{'tools.esptool.cmd'} !~ /\.py$/) {
  print "ESPTOOL_COM?=\$(error esptool must be installed for this operation! Run: pip install esptool)\n";
} else {
  print "ESPTOOL_COM?=$vars{'tools.esptool.path'}/$vars{'tools.esptool.cmd'}\n";
}
print "UPLOAD_COM?=$vars{'tools.esptool.upload.pattern'}\n";

if ($vars{'build.spiffs_start'}) {
  print "SPIFFS_START?=$vars{'build.spiffs_start'}\n";
  my $spiffs_size = sprintf("0x%X", hex($vars{'build.spiffs_end'})-hex($vars{'build.spiffs_start'}));
  print "SPIFFS_SIZE?=$spiffs_size\n";
} elsif ($vars{'build.partitions'}) {
  print "COMMA=,\n";
  print "SPIFFS_SPEC:=\$(subst \$(COMMA), ,\$(shell grep spiffs \$(PART_FILE)))\n";
  print "SPIFFS_START:=\$(word 4,\$(SPIFFS_SPEC))\n";
  print "SPIFFS_SIZE:=\$(word 5,\$(SPIFFS_SPEC))\n";
}
$vars{'build.spiffs_blocksize'} ||= "4096";
print "SPIFFS_BLOCK_SIZE?=$vars{'build.spiffs_blocksize'}\n";
print "MK_FS_COM?=\"\$(MK_FS_PATH)\" -b \$(SPIFFS_BLOCK_SIZE) -s \$(SPIFFS_SIZE) -c \$(FS_DIR) \$(FS_IMAGE)\n";
print "RESTORE_FS_COM?=\"\$(MK_FS_PATH)\" -b \$(SPIFFS_BLOCK_SIZE) -s \$(SPIFFS_SIZE) -u \$(FS_RESTORE_DIR) \$(FS_IMAGE)\n";

my $fs_upload_com = $vars{'tools.esptool.upload.pattern'};
$fs_upload_com =~ s/(.+ -ca) .+/$1 \$(SPIFFS_START) -cf \$(FS_IMAGE)/;
$fs_upload_com =~ s/(.+ --flash_size detect) .+/$1 \$(SPIFFS_START) \$(FS_IMAGE)/;
print "FS_UPLOAD_COM?=$fs_upload_com\n";
my $val = $vars{'recipe.hooks.core.prebuild.1.pattern'};
$val =~ s/bash -c "(.+)"/$1/;
$val =~ s/(#define .+0x)(\`)/"\\$1\"$2/;
$val =~ s/(\\)//;
print "CORE_PREBUILD=$val\n";
print "SKETCH_PREBUILD=$vars{'recipe.hooks.sketch.prebuild.1.pattern'}\n";
print "VTABLE_FLAGS?=$vars{'build.vtable_flags'}\n";
print "LINK_PREBUILD=$vars{'recipe.hooks.linking.prelink.1.pattern'}\n";
print "MEM_FLASH=$vars{'recipe.size.regex'}\n";
print "MEM_RAM=$vars{'recipe.size.regex.data'}\n";
my $flash_info = $vars{'menu.FlashSize.' . $flashSize} || $vars{'menu.eesz.' . $flashSize};
print "FLASH_INFO=$flash_info\n";
print "LWIP_INFO=", $vars{'menu.LwIPVariant.' . $lwipvariant} || $vars{'menu.ip.' . $lwipvariant}, "\n";
