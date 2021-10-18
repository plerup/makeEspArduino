#====================================================================================
# OpenBSD.mk
#
# Specific settings for OpenBSD
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
ARDUINO_ROOT ?= ${LOCALBASE}/share/arduino
ARDUINO_HW_ESP_ROOT = $(ARDUINO_ROOT)/hardware/espressif/$(CHIP)
UPLOAD_PORT_MATCH ?= /dev/tty*U*
CMD_LINE = $(shell ps $$PPID -o command | tail -1)
OS_NAME = openbsd
BUILD_THREADS ?= $(shell sysctl -n hw.ncpuonline)
ARDUINO_LIBS = ${LOCALBASE}/share/arduino/libraries
CUSTOM_LIBS += ${LOCALBASE}/avr/include