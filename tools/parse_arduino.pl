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
# Copyright (c) 2016-2026 Peter Lerup. All rights reserved.
#
#====================================================================================
use strict;

my $esp_root = shift;
my $board = shift;
my $flashSize = shift;
my $partitionScheme = shift;
my $os = shift;
my $lwipvariant = shift;
my %vars;

sub def_var {
  my ($name, $var) = @_;
  print "$var ?= $vars{$name}\n";
  $vars{$name} = "\$($var)";
}

sub multi_com {
  my ($match ) = @_;
  my @result;
  foreach my $name (sort keys %vars) {
    push(@result, $vars{$name}) if $name =~ /^$match$/;
  }
  return join(" && \\\n", @result);
}
# Some defaults and makeEspArduino build-context properties.
# These are re-applied after an arduino-cli property import so CLI resolves the
# board/platform configuration while makeEspArduino remains in control of its
# own build paths and generated file names.
sub set_make_context {
  $vars{'runtime.platform.path'} = $esp_root;
  $vars{'includes'} = '$(C_INCLUDES)';
  $vars{'runtime.ide.version'} = '10605';
  $vars{'runtime.ide.path'} = $esp_root;
  $vars{'build.arch'} = '$(UC_CHIP)';
  $vars{'build.project_name'} = '$(MAIN_NAME)';
  $vars{'build.path'} = '$(BUILD_DIR)';
  $vars{'build.core.path'} = '$(BUILD_DIR)';
  $vars{'object_files'} = '$^ $(BUILD_INFO_OBJ)';
  $vars{'archive_file_path'} = '$(CORE_LIB)';
  $vars{'build.sslflags'} = '$(SSL_FLAGS)';
  $vars{'build.mmuflags'} = '$(MMU_FLAGS)';
  $vars{'build.vtable_flags'} = '$(VTABLE_FLAGS)';
  $vars{'build.source.path'} = '$(dir $(SKETCH))';
  $vars{'build.variant.path'} = '$(ESP_ROOT)/variants/' . $board;
  $vars{'runtime.os'} = '$(OS)';
  $vars{'build.fqbn'} = 'generic';
  $vars{'_id'} = $board;
}

set_make_context();

# Parse the Arduino description files. For a git checkout these are the
# authoritative configuration source, preserving the historical parser
# behavior. For a Boards Manager installation arduino-cli is authoritative;
# here we only retain raw board menu entries needed for makeEspArduino's
# explicit FLASH_DEF/LWIP_VARIANT overrides and verify that the board exists.
my $cli_properties = $ENV{'ARDUINO_CLI_PROPERTIES'};
my %raw_vars;
my $board_defined;
foreach my $fn (@ARGV) {
  my $f;
  open($f, $fn) || die "Failed to open: $fn\n";
  while (<$f>) {
    s/\s+$//;
    next unless /^(\w[\w\-\.]+)=(.*)/;
    my ($raw_key, $raw_val) = ($1, $2);
    $raw_vars{$raw_key} = $raw_val;
    $board_defined = 1 if $raw_key eq "$board.name";

    next if $cli_properties;

    my $key = $raw_key;
    my $val = $raw_val;
    $key =~ s/\.esptool_py\./.esptool./g;
    $val =~ s/\.esptool_py\./.esptool./g;

    # In git-checkout mode, defer board menu entries until all files have
    # been read. Arduino selects one option per menu (the first declared
    # option when no FQBN option is supplied), and the selected menu
    # properties override the base board properties.
    next if $key =~ /^\Q$board\E\.menu\./;

    $key =~ s/^\Q$board\E\.//;
    $vars{$key} ||= $val;
    $vars{$1} = $vars{$key} if $key =~ /(.+)\.$os$/;
  }
  close($f);
}

# Apply Arduino board-menu defaults for a git checkout. The Arduino build
# system selects the first declared option of each menu when the FQBN does not
# explicitly select one. Menu properties then override base board properties.
# makeEspArduino's historical FLASH_DEF and LWIP_VARIANT selectors override the
# corresponding default option when the requested option exists.
unless ($cli_properties) {
  my %menu_default;
  my %menu_selected;

  # Determine the first declared option of every menu, preserving file order.
  foreach my $key (keys %raw_vars) {
    # %raw_vars does not preserve insertion order, so defaults are collected
    # below from the original files in a second lightweight pass.
  }

  foreach my $fn (@ARGV) {
    open(my $f, '<', $fn) || die "Failed to open: $fn\n";
    while (<$f>) {
      s/\s+$//;
      # A menu option is declared by the option label itself:
      #   board.menu.MenuId.OptionId=Display text
      # It may have no subordinate build/upload properties at all.
      # Therefore detect the option from both the label and any nested
      # properties. Otherwise an empty/default option can be skipped and
      # the next option with a .build.* property selected incorrectly.
      next unless /^\Q$board\E\.menu\.([^.]+)\.([^.]+)(?:\..*)?=(.*)$/;
      my ($menu, $option) = ($1, $2);
      $menu_default{$menu} = $option unless exists $menu_default{$menu};
    }
    close($f);
  }

  %menu_selected = %menu_default;

  # Preserve makeEspArduino's explicit selectors where they map to an actual
  # board menu option.
  foreach my $menu (qw(FlashSize eesz)) {
    my $prefix = "$board.menu.$menu.$flashSize.";
    $menu_selected{$menu} = $flashSize
      if grep { index($_, $prefix) == 0 } keys %raw_vars;
  }
  foreach my $menu (qw(LwIPVariant ip)) {
    my $prefix = "$board.menu.$menu.$lwipvariant.";
    $menu_selected{$menu} = $lwipvariant
      if grep { index($_, $prefix) == 0 } keys %raw_vars;
  }

  # ESP32 partition selection is independent of ESP8266 FLASH_DEF.
  if ($partitionScheme) {
    my $prefix = "$board.menu.PartitionScheme.$partitionScheme.";
    $menu_selected{'PartitionScheme'} = $partitionScheme
      if grep { index($_, $prefix) == 0 } keys %raw_vars;
  }

  # Apply the selected option of every menu. Assignment (not ||=) is
  # intentional: Arduino menu properties override base board properties.
  foreach my $key (keys %raw_vars) {
    next unless $key =~ /^\Q$board\E\.menu\.([^.]+)\.([^.]+)\.(.+)$/;
    my ($menu, $option, $dst) = ($1, $2, $3);
    next unless defined $menu_selected{$menu} && $option eq $menu_selected{$menu};
    $dst =~ s/\.esptool_py\./.esptool./g;
    my $val = $raw_vars{$key};
    $val =~ s/\.esptool_py\./.esptool./g;
    $vars{$dst} = $val;
    $vars{$1} = $vars{$dst} if $dst =~ /(.+)\.$os$/;
  }
}

# For a Boards Manager installation import the *complete* board/platform
# property set selected by Arduino CLI. The makefile requests
# --show-properties=unexpanded: Arduino therefore performs the difficult work
# of selecting board/menu defaults and package dependencies, while references
# such as {build.flash_mode} remain available for makeEspArduino substitutions.
if ($cli_properties) {
  die "* Missing arduino-cli property file $cli_properties\n" unless -s $cli_properties;
  my $f;
  open($f, $cli_properties) || die "Failed to open: $cli_properties\n";
  while (<$f>) {
    s/\s+$//;
    next unless /^(\w[\w\-\.]+)=(.*)/;
    my ($key, $val) = ($1, $2);
    $key =~ s/\.esptool_py\./.esptool./g;
    $val =~ s/\.esptool_py\./.esptool./g;
    $vars{$key} = $val;
  }
  close($f);

  # CLI properties may contain build-context values meaningful to Arduino's
  # own build command. Restore makeEspArduino's corresponding placeholders.
  set_make_context();

  # Preserve makeEspArduino's explicit flash-size, partition, and LwIP selectors. These
  # are user-facing make variables predating FQBN board options. Apply all
  # properties belonging to the requested menu option on top of the CLI
  # defaults, without reimplementing default-menu selection.
  foreach my $spec (
      [ qr/^\Q$board\E\.menu\.(?:FlashSize|eesz)\.\Q$flashSize\E\.(.+)$/, 'flash' ],
      [ qr/^\Q$board\E\.menu\.(?:LwIPVariant|ip)\.\Q$lwipvariant\E\.(.+)$/, 'lwip' ],
      [ qr/^\Q$board\E\.menu\.PartitionScheme\.\Q$partitionScheme\E\.(.+)$/, 'partition' ]) {
    my ($re, $kind) = @$spec;
    next if $kind eq 'partition' && !$partitionScheme;
    foreach my $key (keys %raw_vars) {
      next unless $key =~ $re;
      my $dst = $1;
      $dst =~ s/\.esptool_py\./.esptool./g;
      $vars{$dst} = $raw_vars{$key};
    }
  }
}

die "* Unknown board $board\n" unless $board_defined;

# Disable the new options handling as makeEspArduino already has this functionality
$vars{'build.opt.flags'} = "";
$vars{'upload.resetmethod'} ||= "--before default_reset --after hard_reset";
print "# Board definitions\n";
def_var('build.code_debug', 'CORE_DEBUG_LEVEL');
def_var('build.f_cpu', 'F_CPU');
def_var('build.flash_mode', 'FLASH_MODE');
def_var('build.cdc_on_boot', 'CDC_ON_BOOT');
def_var('build.flash_freq', 'FLASH_SPEED');
def_var('upload.resetmethod', 'UPLOAD_RESET');
def_var('upload.speed', 'UPLOAD_SPEED');
$vars{'serial.port'} = '$(UPLOAD_PORT)';

# Arduino tool recipes use a local property namespace. For example, inside
# tools.esptool.upload.pattern, {path}, {cmd}, {upload.flash_prefix} and
# {upload.pattern_args} refer to properties below tools.esptool.*. Qualify
# every such reference before the normal global expansion below. This keeps
# the parser aligned with the Arduino platform specification as new tool-local
# properties are added, instead of special-casing individual placeholders.
foreach my $key (keys %vars) {
  next unless $key =~ /^tools\.([^.]+)\./;
  my $tool = $1;
  $vars{$key} =~ s/\{([\w\-\.]+)\}/
    exists $vars{"tools.$tool.$1"} ? "{tools.$tool.$1}" : "{$1}"
  /gex;
}

# Some platform versions include upload.pattern_args in upload.pattern, while
# older ones expect the caller to append it. Remember which form this
# platform uses before property expansion so arguments are emitted exactly once.
my $upload_pattern_has_args = $vars{'tools.esptool.upload.pattern'} =~
  /\{(?:tools\.esptool\.)?upload\.pattern_args\}/;

$vars{'compiler.cpreprocessor.flags'} .= " \$(C_PRE_PROC_FLAGS)";
$vars{'build.extra_flags'} .= " \$(BUILD_EXTRA_FLAGS)";
# Expand all variables
foreach my $key (sort keys %vars) {
  while ($vars{$key} =~/\{/) {
    $vars{$key} =~ s/\{([\w\-\.]+)\}/$vars{$1}/;
    $vars{$key} =~ s/""//;
  }
  # Some additional replacements
  $vars{$key} =~ s/ -o\s+$//;
  $vars{$key} =~ s/(-D\w+=)"([^"]+)"/$1\\"$2\\"/g;
}
def_var('compiler.warning_flags', 'COMP_WARNINGS');
# Print the makefile content
my $val;
print("MCU = $vars{'build.mcu'}\n");
print "INCLUDE_VARIANT = $vars{'build.variant'}\n";
print "VTABLE_FLAGS?=-DVTABLES_IN_FLASH\n";
print "MMU_FLAGS?=-DMMU_IRAM_SIZE=0x8000 -DMMU_ICACHE_SIZE=0x8000\n";
print "SSL_FLAGS?=\n";
print "BOOT_LOADER?=$esp_root/bootloaders/eboot/eboot.elf\n";
# ESP32 defines esptool through tools.esptool.*, while ESP8266 uses
# runtime.tools.esptool.path together with compiler.elf2hex.cmd.
# Use the properties supplied by the platform instead of assuming either layout.
my $esptool_path = $vars{'tools.esptool.path'}
                || $vars{'tools.esptool_py.path'}
                || $vars{'runtime.tools.esptool.path'};
my $esptool_cmd = $vars{'tools.esptool.cmd'}
               || $vars{'tools.esptool_py.cmd'}
               || $vars{'compiler.elf2hex.cmd'};
if ($esptool_cmd) {
  my $esptool_file = $esptool_cmd;
  # Some platforms, notably ESP8266 git checkouts, define cmd as an
  # absolute executable path and leave tools.esptool.path empty.
  if ($esptool_cmd !~ m{^(?:/|[A-Za-z]:[\\/])} && $esptool_path) {
    $esptool_file = "$esptool_path/$esptool_cmd";
  }
  print "ESPTOOL_FILE = $esptool_file\n";
}

if ($ENV{'ARDUINO_CLI_PROPERTIES'}) {
  my $fs_tool = $ENV{'MK_FS_MATCH'};
  if ($fs_tool) {
    my $fs_path = $vars{"runtime.tools.$fs_tool.path"} || $vars{"tools.$fs_tool.path"};
    die "* arduino-cli did not resolve runtime.tools.$fs_tool.path\n" unless $fs_path;
    my $fs_cmd = $vars{"tools.$fs_tool.cmd"} || $fs_tool;
    print "MK_FS_PATH = $fs_path/$fs_cmd\n";
  }
}
print "# Commands\n";
print "C_COM=\$(C_COM_PREFIX) $vars{'recipe.c.o.pattern'}\n";
print "CPP_COM=\$(CPP_COM_PREFIX) $vars{'recipe.cpp.o.pattern'}\n";
print "S_COM=$vars{'recipe.S.o.pattern'}\n";
print "LIB_COM=\"$vars{'compiler.path'}$vars{'compiler.ar.cmd'}\" $vars{'compiler.ar.flags'}\n";
print "CORE_LIB_COM=$vars{'recipe.ar.pattern'}\n";
print "LD_COM=$vars{'recipe.c.combine.pattern'}\n";
print "PART_FILE?=$esp_root/tools/partitions/default.csv\n" unless $vars{'build.partitions'};
$val = $vars{'recipe.objcopy.eep.pattern'} || $vars{'recipe.objcopy.partitions.bin.pattern'};
$val =~ s/\"([^\"]+\.csv)\"/\$(PART_FILE)/;
print "GEN_PART_COM=$val\n";
($val = multi_com('recipe\.objcopy\.hex.*\.pattern')) =~ s/[^"]+\/bootloaders\/eboot\/eboot.elf/\$(BOOT_LOADER)/;
$val ||= multi_com('recipe\.objcopy\.bin.*\.pattern');
print "OBJCOPY=$val\n";
print "SIZE_COM=$vars{'recipe.size.pattern'}\n";
my $upload_com = $vars{'tools.esptool.upload.pattern'};
$upload_com .= " $vars{'tools.esptool.upload.pattern_args'}" unless $upload_pattern_has_args;
print "UPLOAD_COM?=$upload_com\n";
if ($vars{'build.spiffs_start'}) {
  # ESP8266 keeps the historical build.spiffs_* names even for LittleFS.
  print "FS_START?=$vars{'build.spiffs_start'}\n";
  my $fs_size = sprintf("0x%X",
    hex($vars{'build.spiffs_end'}) - hex($vars{'build.spiffs_start'}));
  print "FS_SIZE?=$fs_size\n";
} elsif ($vars{'build.partitions'}) {
  # ESP32 PREBUILD resolves the selected partition table here.
  print "PART_FILE?=\$(BUILD_DIR)/partitions.csv\n";
  print "COMMA=,\n";
  # Keep these recursive so partition parsing only happens when an FS target
  # actually needs the values. Dollar signs are doubled for GNU Make so awk
  # receives its own field references ($2 and $3).
  print "FS_SPEC=\$(subst \$(COMMA), ,\$(shell awk -F, '/^[[:space:]]*#/ {next} {gsub(/[[:space:]]/,\"\",\$\$2); gsub(/[[:space:]]/,\"\",\$\$3); if (\$\$2 == \"data\" && \$\$3 == \"spiffs\") {print; exit}}' \$(PART_FILE)))\n";
  print "FS_START=\$(word 4,\$(FS_SPEC))\n";
  print "FS_SIZE=\$(word 5,\$(FS_SPEC))\n";
}
$vars{'build.spiffs_blocksize'} ||= "4096";
print "FS_BLOCK_SIZE?=$vars{'build.spiffs_blocksize'}\n";
print "MK_FS_COM?=\"\$(MK_FS_PATH)\" -b \$(FS_BLOCK_SIZE) -s \$(FS_SIZE) -c \$(FS_DIR) \$(FS_IMAGE)\n";
print "RESTORE_FS_COM?=\"\$(MK_FS_PATH)\" -b \$(FS_BLOCK_SIZE) -s \$(FS_SIZE) -u \$(FS_RESTORE_DIR) \$(FS_IMAGE)\n";
my $fs_upload_com = $upload_com;
$fs_upload_com =~ s/(.+ -ca) .+/$1 \$(FS_START) -cf \$(FS_IMAGE)/;
$fs_upload_com =~ s/(.+ --flash_size \S+) .+/$1 \$(FS_START) \$(FS_IMAGE)/;
print "FS_UPLOAD_COM?=$fs_upload_com\n";
$val = multi_com('recipe\.hooks*\.prebuild.*\.pattern');
$val =~ s#/usr/bin/env ##g;
$val =~ s/bash -c "(.+)"/$1/g;
$val =~ s/(#define .+0x)(\`)/"\\$1\"$2/;
print "PREBUILD=$val\n";
print "PRELINK=", multi_com('recipe\.hooks\.linking\.prelink.*\.pattern'), "\n";
print "MEM_FLASH=$vars{'recipe.size.regex'}\n";
print "MEM_RAM=$vars{'recipe.size.regex.data'}\n";
my $flash_info = $vars{'menu.FlashSize.' . $flashSize} || $vars{'menu.eesz.' . $flashSize};
print "FLASH_INFO=$flash_info\n" if $flashSize;
my $partition_info = $vars{'menu.PartitionScheme.' . $partitionScheme};
print "PARTITION_INFO=$partition_info\n" if $partitionScheme;
print "LWIP_INFO=", $vars{'menu.LwIPVariant.' . $lwipvariant} || $vars{'menu.ip.' . $lwipvariant}, "\n";
