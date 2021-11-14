#====================================================================================
# Window_NT.mk
#
# Specific settings for Cygwin
#
# This file is part of makeESPArduino
# License: LGPL 2.1
# General and full license information is available at:
#    https://github.com/plerup/makeEspArduino
#
# Copyright (c) 2021 Peter Lerup. All rights reserved.
#
#====================================================================================

CONFIG_ROOT ?= $(shell cygpath -m $(LOCALAPPDATA))
ARDUINO_ROOT ?= $(shell cygpath -m $(LOCALAPPDATA)/Arduino15)
OS_NAME = windows
BUILD_DIR := $(shell cygpath -m /tmp/mkESP)
ARDUINO_LIBS := $(shell cygpath -m $(HOMEDRIVE)/$(HOMEPATH)/Documents/Arduino/libraries)
