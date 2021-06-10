#====================================================================================
# Darwin.mk
#
# Specific settings for Macintosh OS X
#
# This file is part of makeESPArduino
# License: LGPL 2.1
# General and full license information is available at:
#    https://github.com/plerup/makeEspArduino
#
# Copyright (c) 2021 Peter Lerup. All rights reserved.
#
#====================================================================================

CONFIG_ROOT ?= $(HOME)/Library
ARDUINO_ROOT ?= $(HOME)/Library/Arduino15
UPLOAD_PORT_MATCH ?= /dev/tty.usb*
CMD_LINE = $(shell ps $$PPID -o command | tail -1)
OS_NAME = macosx
BUILD_THREADS ?= $(shell sysctl -n hw.ncpu)
