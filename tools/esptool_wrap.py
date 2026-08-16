#!/usr/bin/env python3
#====================================================================================
# ESP8266 esptool launcher
#
# Loads the esptool and pyserial packages installed by the ESP8266 Arduino tools/get.py
# script and passes all remaining arguments directly to esptool.
#
# This file is part of makeESPArduino
# License: LGPL 2.1
# General and full license information is available at:
#    https://github.com/plerup/makeEspArduino
#
# Copyright (c) 2026 Peter Lerup. All rights reserved.
#
#====================================================================================

import pathlib
import sys

if len(sys.argv) < 2:
    sys.stderr.write("Usage: esptool_wrap.py <esp-tools-dir> [esptool arguments...]\n")
    sys.exit(2)

tools_dir = pathlib.Path(sys.argv[1]).resolve()
sys.argv = [sys.argv[0]] + sys.argv[2:]

# Match the module setup used by ESP8266 Arduino's tools/upload.py.
for module in ("pyserial", "esptool"):
    sys.path.insert(0, str(tools_dir / module))

try:
    import esptool
except ImportError as exc:
    sys.stderr.write(f"* Failed to load ESP8266 esptool from {tools_dir}: {exc}\n")
    sys.exit(2)

esptool.main(sys.argv[1:])
