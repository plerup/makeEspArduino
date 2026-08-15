# makeEspArduino

A Makefile-based build system for ESP8266 and ESP32 Arduino projects.

makeEspArduino provides a command-line build environment for the
[ESP8266 Arduino core](https://github.com/esp8266/Arduino) and
[Arduino-ESP32](https://github.com/espressif/arduino-esp32). It is
intended for projects that want to remain compatible with the Arduino
ecosystem while using `make` for reproducible, automated, or
production-oriented builds.

The build recipes are derived from the Arduino core's `platform.txt`,
`boards.txt`, and related configuration files rather than being
duplicated in the Makefile. Source and library dependencies are
discovered recursively from `#include` directives, and libraries may be
located outside the directory hierarchy required by the Arduino IDE.

makeEspArduino supports:

-   ESP8266 and ESP32 Arduino cores
-   Arduino Boards Manager installations
-   Explicit ESP Arduino git checkouts
-   automatic source and library discovery
-   serial, OTA, and HTTP upload
-   SPIFFS and LittleFS images
-   parallel builds and ccache
-   Visual Studio Code configuration generation
-   crash and memory analysis tools

## Environment modes

There are two ways to provide the ESP Arduino core.

### Arduino package installation

If `ESP_ROOT` is **not** specified, makeEspArduino uses an ESP8266 or
ESP32 core installed through the Arduino package system.

`arduino-cli` is required in this mode. It is used as the authoritative
resolver for:

-   the installed platform location
-   the selected board and its default menu settings
-   compiler and SDK locations
-   esptool and other package-managed tools
-   Arduino build and upload properties

This avoids depending on the internal directory structure used by
Arduino Boards Manager.

The actual compilation and dependency handling are still performed by
makeEspArduino; Arduino CLI is used for configuration and package
resolution.

### Git checkout

If `ESP_ROOT` is specified, it must point to an ESP8266 Arduino or
Arduino-ESP32 git checkout.

For example:

``` sh
make -f makeEspArduino.mk ESP_ROOT=~/esp8266 ...
```

or:

``` sh
make -f makeEspArduino.mk ESP_ROOT=~/esp32 CHIP=esp32 ...
```

In this mode the selected checkout is used directly. This is useful when
a project needs strict control over the framework version, uses the
framework as a git submodule, or builds against an unreleased
development branch.

The required compiler and tools must have been installed using the setup
procedure provided by the corresponding upstream repository.

## Requirements

The basic host requirements are:

-   GNU Make
-   Perl
-   Python 3
-   [pyserial](https://pyserial.readthedocs.io/)
-   the tools required by the selected ESP Arduino core

For an Arduino package installation, `arduino-cli` is also required.

pyserial is used for USB serial-port discovery and the built-in serial
monitor. It can normally be installed with:

``` sh
python3 -m pip install pyserial
```

Clone makeEspArduino with:

``` sh
git clone https://github.com/plerup/makeEspArduino.git
cd makeEspArduino
```

## Quick start

### Using an Arduino package installation

Install the desired core using Arduino IDE Boards Manager or Arduino
CLI. For example:

``` sh
arduino-cli core install esp8266:esp8266
```

or:

``` sh
arduino-cli core install esp32:esp32
```

Build and flash the demo for ESP8266:

``` sh
make -f makeEspArduino.mk DEMO=1 flash
```

For ESP32:

``` sh
make -f makeEspArduino.mk CHIP=esp32 DEMO=1 flash
```

For a specific board, set `BOARD` to its Arduino board identifier:

``` sh
make -f makeEspArduino.mk CHIP=esp32 BOARD=XIAO_ESP32C6 DEMO=1 flash
```

Available board identifiers can be displayed with:

``` sh
make -f makeEspArduino.mk CHIP=esp32 list_boards
```

### Using an ESP8266 git checkout

``` sh
git clone https://github.com/esp8266/Arduino.git ~/esp8266
cd ~/esp8266
git submodule update --init
cd tools
python3 get.py
```

Then build with:

``` sh
cd ~/makeEspArduino
make -f makeEspArduino.mk ESP_ROOT=~/esp8266 DEMO=1 flash
```

When changing tags or branches, rerun the upstream tool installation
procedure if required by that version.

### Using an ESP32 git checkout

``` sh
git clone https://github.com/espressif/arduino-esp32.git ~/esp32
cd ~/esp32
git submodule update --init
cd tools
python3 get.py
```

Then:

``` sh
cd ~/makeEspArduino
make -f makeEspArduino.mk ESP_ROOT=~/esp32 CHIP=esp32 DEMO=1 flash
```

Always follow the tool-installation instructions for the particular
upstream core version; these procedures may change between releases.

## Getting help

The Makefile contains descriptions of the available targets,
configuration variables, and their defaults:

``` sh
make -f makeEspArduino.mk help
```

If the shortcut command has been installed:

``` sh
espmake help
```

## Building projects

If `SKETCH` is not specified, makeEspArduino looks for a sketch in the
current directory.

Build a sketch in the current directory:

``` sh
espmake
```

Specify a sketch explicitly:

``` sh
espmake SKETCH=/path/to/project/project.ino
```

A sketch inside the selected ESP Arduino tree can also be referenced
through `ESP_ROOT`:

``` sh
espmake SKETCH="$(ESP_ROOT)/libraries/Ticker/examples/TickerBasic/TickerBasic.ino"
```

Common targets include:

``` sh
espmake
espmake flash
espmake run
espmake clean
espmake list_boards
espmake list_lib
```

## Selecting the target

`CHIP` selects the platform:

``` text
esp8266
esp32
```

ESP8266 is the default. Set `CHIP=esp32` for ESP32-family targets.

`BOARD` is the board identifier from the Arduino core's `boards.txt`,
not necessarily the display name shown by the Arduino IDE.

Examples:

``` sh
espmake CHIP=esp8266 BOARD=generic
espmake CHIP=esp32 BOARD=esp32
espmake CHIP=esp32 BOARD=XIAO_ESP32C6
```

Use `list_boards` to see the board identifiers available in the selected
core:

``` sh
espmake CHIP=esp32 list_boards
```

Board-specific Arduino menu defaults are applied when the configuration
is generated. They can then be overridden through the corresponding
makeEspArduino variables where supported.

### Flash layout and partitions

ESP8266 and ESP32 use different flash-layout models.

For ESP8266, `FLASH_DEF` selects the flash layout from the board's
`eesz` / flash-size menu. That selection controls the application layout
and the filesystem region.

For ESP32, `FLASH_DEF` is not used. Flash layout is defined by a
partition table. `PARTITION_SCHEME` can be used to select an Arduino
`PartitionScheme` menu entry, for example:

``` sh
espmake CHIP=esp32 BOARD=esp32 PARTITION_SCHEME=huge_app
```

If `PARTITION_SCHEME` is empty, the board/core default is used. A custom
partition table can still be supplied through `PART_FILE` where
supported by the selected core/build flow.

## Inspecting the resolved configuration

makeEspArduino writes the effective Arduino configuration to:

``` text
$(BUILD_DIR)/arduino.mk
```

This is the first place to look when comparing a makeEspArduino build
with Arduino IDE/CLI behavior. It contains resolved values and recipes
such as:

``` make
F_CPU ?= 160000000L
FLASH_MODE ?= dio
MCU = esp32c6
INCLUDE_VARIANT = XIAO_ESP32C6
```

as well as compiler, linker, prebuild, partition, and upload commands.

For additional build diagnostics:

``` sh
espmake VERBOSE=1
```

## Configuration

Configuration variables can be supplied on the command line:

``` sh
espmake BOARD=generic UPLOAD_PORT=/dev/ttyUSB0
```

For persistent project settings, create a `config.mk` in the current
directory or in the sketch directory. makeEspArduino will include it
automatically.

Example:

``` make
BOARD = XIAO_ESP32C6
CHIP = esp32
UPLOAD_PORT = /dev/ttyACM0
LIBS += $(ROOT)/libraries
```

Alternatively, a project Makefile can define its variables before
including makeEspArduino:

``` make
SKETCH = $(CURDIR)/MyProject.ino
BOARD = generic

include $(HOME)/makeEspArduino/makeEspArduino.mk
```

A different project configuration file can be selected with `PROJ_CONF`.

A global `config.mk` can also be used. Its default location is
operating-system dependent and can be changed with
`MAKEESPARDUINO_CONFIGS_ROOT`.

## Shortcut commands

The `install` target can create the `espmake`/`espmake32` shortcut
commands:

``` sh
make -f makeEspArduino.mk ESP_ROOT=~/esp8266 install
make -f makeEspArduino.mk ESP_ROOT=~/esp32 CHIP=esp32 install
```

Installation to the default system location may require elevated
privileges.

#### Advanced usage

The makefile has several variables which control the build. There are
different ways to change the defaults of these variables.

The simplest and most direct way to do this is by specifying the
variables and their values on the command line.

The more permanent way is to create a special makefile with the
appropriate values for the variables and then include this in the build.
This can be achieved either by including makeEspArduino.mk in this file
or the other way around by letting makeEspArduino.mk include it. The
advantage with the latter method is that the makefile doesn't need to
know the location of makeEspArduino.mk, more about this in the examples
below.

The most important variables in the makefile are listed below:

**SKETCH** is the path to the main source file. As stated above, if this
is missing then makeEspArduino will try to locate it in the current
directory.

**LIBS** is a variable which is used to specify your own additional
library source or linker archive files. As stated above, makeEspArduino
will do an automatic search for header files used by all involved source
files in the build. This is achieved by checking for *#include*
statements and for each found such statement, search for a corresponding
existing header file anywhere in a list of directories. The search is
started in the sketch source file and then recursively following any
found file which in turn will be searched for new *#include* statements.
By default this list contains all the directories underneath the
ESP/Arduino *libraries* root and possible standard Arduino libraries,
but the list can be extended using this variable.

This way you can specify an additional list of directories which
contains header and/or source files that you want to be included in the
build. The different entries in the list are separated with space. If an
entry contains a path to a directory then that directory and all its sub
directories will be included in the search list for header files. If a
header file is found in that directory then all source files (*.cpp,
*.c, \*.S) also found there will be added to the build. This is due to
the fact that there is not always a one-to-one relationship between a
header file name and the corresponding implementation source file.

It is also possible to specify an explicit source file or a wildcard in
a list entry. In that case only the source files matching this will be
added and the corresponding directory will added to the header file
directory search list.

Library files (.a or .lib) can also be specified here and these will be
added to the linker command.

If the sketch is located in an */example/* directory the possible
corresponding */src/* directory will automatically be added to the
directory search list.

Example:

    LIBS = $(MY_ROOT)/lib1 $(MY_ROOT)/lib2/my_file.cpp $(MY_ROOT)/lib3/*.c $(MY_ROOT)/lib3/my_lib.a

You can always use the rule **list_lib** to check what include
directories and source files that was found during the search.

The automatic search for used files via included header files does not
work if the corresponding implementation source file are located in
another directory than the header file. If you have problem with this,
you can set the variable **EXPAND_LIBS** and then all source files in
the directories specified via the LIBS variable will be added to the
build. This may lead to compiling unnecessary files though.

If you for some reason want to exclude some sub directories from the
search list you can specify this using the variable **EXCLUDE_DIRS**.
The value is interpreted a regular expressions so multiple directories
must be separated with \| . In the same way the variable **EXCLUDE_INC**
can be used to exclude directories from the list of found include
directories.

**CHIP** Set to either esp8266 (default) or esp32

**BOARD** The type of ESP8266 or ESP32 board you are using. Use the rule
**list_boards** to show what's available.

**FLASH_DEF** selects the ESP8266 flash layout. It is not used for
ESP32.

**PARTITION_SCHEME** selects an ESP32 Arduino `PartitionScheme` menu
entry. If it is not specified, the board/core default partition scheme
is used.

**BUILD_DIR** All intermediate build files (object, map files etc.) are
stored in a separate directory controlled by this variable. By default
this is set to a name consisting of the project and board names. This is
just the directory name, the root of this directory is controlled by the
variable **BUILD_ROOT**. Default for this is /tmp/mkESP but it can be
set to a non-temporary location if so is desired.

**BUILD_EXTRA_FLAGS** this variable can be setup to add additional
parameters for the compilation commands. It will be placed last and
thereby it is possible to override the preceding default ones.

It is also possible to set file specific compilation parameters by
defining a variable which starts with the name of the actual source file
followed by the string \*\*\_CFLAGS\*\*. Example:

    my_class.cpp_CFLAGS = -DOPTION=1

In this case the parameter -DOPTION=1 will be applied when compiling the
file *m_class.cpp*. Please note that just the file name, not the path,
should be used.

There are some other important variables which corresponds to the
settings which you normally do in the "Tools" menu in the Arduino IDE.
The makefile will parse the Arduino IDE configuration files and use the
same defaults as you would get when after selecting a board in the
"Tools" menu.

The result of the parsing is stored as variables in a separate
intermediate makefile named 'arduino.mk' in the directory defined by the
variable **BUILD_DIR**. Look into this file if you need to control even
more detailed settings variables.

**VERBOSE** Define this variable if you want to trace all the executed
operations in the build

As stated above you can always get a description of all makefile
operations, configuration variables and their default values via the
'help' function

    espmake help

##### Build time and version information

makeEspArduino automatically generates header and C source files
containing information about the time when the build (link) was
performed. The generated information also includes the git descriptions
(tags) of the ESP Arduino environment and project source, when
applicable. This can be used by project source files to provide
stringent version information from within the software. The information
is stored in a global struct variable named `_BuildInfo` with the
following string constant fields:

| Name | Value |
| --- | --- |
| **src_version** | Source code git version |
| **date** | Build date |
| **time** | Build time |
| **env_version** | ESP Arduino version |

##### Including the makefile

The easiest way to control the makefile is by defining the desired
values of the control variables in your own makefile and then include
makeEspArduino.mk. Example:

    # My makefile
    SKETCH = $(ESP_ROOT)/libraries/Ticker/examples/TickerBasic/TickerBasic.ino

    UPLOAD_PORT = /dev/ttyUSB1
    BOARD = esp210

    include $(HOME)/makeEspArduino/makeEspArduino.mk

Another possibility is to do this the other way around, i.e. let
makeEspArduino include your makefile instead. This can be achieved by
naming your makefile "config.mk". makeEspArduino will always check for a
file with this name in the current directory or in the same directory as
the sketch. If you want to use another name for your makefile you can
specify this via the variable PROJ_CONF on the command line. Example of
such a makefile:

    # config.mk
    THIS_DIR := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
    ROOT := $(THIS_DIR)/..
    LIBS =  \
      $(ROOT)/libraries \
      $(ROOT)/ext_lib

    UPLOAD_SPEED = 115200

It is of course also always possible to control the variable values in
the makefile by defining them as environment variables in the shell.
Example:

    export UPLOAD_PORT=/dev/ttyUSB2

A global config file which will apply to all builds can also be defined.
The name of this file is also "config.mk". The location of this file can
be defined via the variable **MAKEESPARDUINO_CONFIGS_ROOT** The default
value is the OS specific standard config directory, i.e.

    Linux:  $(HOME)/.config/makeEspArduino (or $(XDG_CONFIG_HOME)/makeEspArduino)
    Mac:    $(HOME)/Library/makeEspArduino
    CygWin: $(LOCALAPPDATA)/makeEspArduino

Please note that the local config file can always override definitions
in the global one.

#### Flash operations

Serial flashing uses the upload recipe defined by the selected ESP
Arduino core.

For an Arduino package installation, the compiler, esptool, filesystem
tools and other external package dependencies are resolved by Arduino
CLI. makeEspArduino does not depend on their physical layout under the
Arduino package directory.

For a git checkout, the required tools must first be installed using the
setup procedure supplied by the corresponding ESP8266 or ESP32 Arduino
repository.

The serial port is controlled by `UPLOAD_PORT`. If it is not specified,
makeEspArduino uses pyserial to select the first detected USB serial
port. Set `UPLOAD_PORT` explicitly when several USB serial devices are
connected or when a non-USB serial port should be used.

The upload baud rate is controlled by `UPLOAD_SPEED`. Its default is
taken from the selected board configuration. Higher speeds such as
921600 may work depending on the board and host interface.

#### Building a filesystem

There are also rules in the makefile which can be used for building and
uploading a complete flash filesystem to the ESP. This is basically the
same functionality as the one available in the Arduino IDE,
https://github.com/esp8266/Arduino/blob/master/doc/filesystem.rst#uploading-files-to-file-system

LittleFS is the default filesystem. SPIFFS remains available for
existing projects by setting **FS_TYPE=spiffs**. The selected filesystem
is specified with the **FS_TYPE** variable.

For ESP8266, the size and flash location are determined by the selected
`FLASH_DEF` and exposed by the core through its historical
`build.spiffs_*` properties. For ESP32, makeEspArduino uses the
partition table selected by `PARTITION_SCHEME` (or the board/core
default) and resolved by the core's prebuild step at
`$(BUILD_DIR)/partitions.csv`.

The filesystem content is made up of everything within a directory
specified via the variable **FS_DIR**. By default this variable is set
to a subdirectory named **data** in the sketch directory.

Use the rule **flash_fs** or **ota_fs** to generate a filesystem image
and upload it to the ESP.

All the settings for the filesystem are taken from the selected board's
configuration.

It is also possible to dump and recreate the complete filesystem from
the device via the rule **dump_fs**. The corresponding flash section
will be extracted and the individual files recreated in a directory in
the build structure.

#### Specifying custom partition schemes

You may wish to specify a custom partitioning table, as defined in the
[ESP32
docs](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/partition-tables.html).
You can do this by changing the **PART_FILE** variable in your make
file. The default partition table is taken from the selected board/core
configuration. Set `PART_FILE` when an explicit custom partition table
is required.

#### Additional flash I/O operations

The makefile has rules for dumping and restoring the whole flash memory
contents to and from a file. This can be convenient for saving a
specific state or software for which no source code is available.

The rules are named **dump_flash** and **restore_flash**. The name of
the output/input file is controlled by the variable **FLASH_FILE**. The
default value for this is "esp_flash.bin". All required parameters for
the operations are taken from the variables mentioned above for flash
size, serial port and speed etc.

Example:

    espmake dump_flash FLASH_FILE=my_flash.bin

#### Building an object file library

It is also possible to build a library containing all the object files
referenced in the build (excluding the sketch itself). This can e.g. be
used to build separately compiled version controlled libraries which are
then used in other build projects.

Example:

    espmake lib

#### Monitor

makeEspArduino provides a **monitor** target for connecting to the
board's serial port. By default it uses the included
`tools/miniterm.py`, a small wrapper around pyserial's miniterm
implementation. The wrapper exits cleanly without a Python traceback on
serial errors and allows project-specific modification of complete
output lines.

The monitor port defaults to `UPLOAD_PORT`, and the default baud rate is
115200. The monitor command can be replaced completely with
`MONITOR_COM`.

To modify monitor output, provide a Python module named
`miniterm_patch.py` that is importable by the monitor process and
defines:

``` python
def patch_line(line: str):
    return line
```

The function is called for every complete line received from the serial
port. It can be used for filtering, timestamping, colorization,
decoding, or other project-specific output transformations. If the
module is not available, the output is passed through unchanged.

The **run** target performs a combined flash and monitor operation.

#### Misc build features

##### Using ccache

If you want to speed up your builds with makeEspArduino you can install
ccache on your system, https://ccache.dev/

Once installed makeEspArduino will automatically use it during the build
by preceding all C and C++ compilation commands with ccache.

In case you have ccache installed but don't want to use it for the
build, you can set the variable **USE_CCACHE=0**

##### Cross compilation

If you want some other prefix to the C compiler command line the
following variables are available: **C_COM_PREFIX** and
**CPP_COM_PREFIX**

##### Parallel builds

The actual make operation is performed using parallel build compilation
threads. By default all CPU cores of the machine are used. You can
however limit the number of compilation threads started by setting the
**BUILD_THREADS** variable to a desired alternate number.

##### Automatic rebuild

A record of the command line parameters and git versions used in the
last build is stored in the build directory. If any of these are changed
during the next build, e.g. changing a variable definition, a complete
rebuild is made in order to ensure that all possible changes are
applied. If you don't want this function just define the variable
**IGNORE_STATE**.

##### Intermediate object archive

By default all object files are put into an archive as this seems to
enable the linker to remove 5 kB RAM of unused variables. This is the
same method that is used by the Arduino IDE. Unfortunately this might
break some builds e.g. if some special linker flags are used. To disable
this feature set the **NO_USER_OBJ_LIB** to 1.

#### User defined make rules

makeEspArduino has make rules for all the types of input files that are
normally part of a build of Arduino for esp. If you want to add other
type of files there are two variables which can be used for this
purpose.

**USER_SRC_PATTERN** Files matching this pattern will be included in the
automatic search for source files. Must be prefixed with a "\|".
Example:

    USER_SRC_PATTERN = |my_ext

**USER_RULES** This variable is used to define the path to a makefile
which contains the actual make rules for the user specific source files.
Example of contents for such a file:

    $(BUILD_DIR)/%.my_ext.o: %.my_ext
      echo Running my make rule for $<
      my_command $<

#### Setting used version of ESP Arduino

The rule **set_git_version** can be used to control which version tag to
be used in the git repo specified via **ESP_ROOT**. It will perform the
necessary git and copy operations to ensure that the repo is setup
correctly for the tag specified via the variable **REQ_GIT_VERSION**.
Example:

    espmake set_git_version REQ_GIT_VERSION=2.6.3

#### Using Visual Studio Code

Visual Studio Code is a great editor which can be used together with
makeEspArduino. The makefile contains a rule named "vscode". When
invoked it will generate a config file for the C/C++ addin. This will
contain all the required definitions for the IntelliSense function. The
information is based on the parameters of the c/c++ compilation command.

It will also generate contents in the "tasks" configuration file which
enables building with makeEspArduino from within the editor. This is
convenient for stepping through compilation errors for instance.

The configuration files will have settings with the name of the main
sketch.

The workspace directory for the settings files will be ".vscode" and
this can either be automatically detected by makeEspArduino or be
specified via the variable **VS_CODE_DIR**. Automatic here means
checking the parent directories of the sketch for a config directory and
if doesn't exist then the sketch directory itself will be used and
created if not found. If an existing project file (\*.code-workspace) is
found in that directory it will be used as input for the launch of VS
Code.

After generating the configuration files makeEspArduino will launch
Visual Studio (if available in the path)

#### Crash analysis

The rule **crash** will enable you to paste the output of a program
crash for esp8266 or esp32. Explanatory reason and call stack traceback
will be listed with source file and line number for each call found.

#### Compiler preprocessor

Sometimes it can be useful to see the actual full source file content
once all include files and macros have been expanded. The rule
**preproc** is available for this purpose. The path of the source file
to be analyzed is specified via the variable **SRC_FILE**. Example:

    espmake preproc SRC_FILE=my_file.ino

#### Memory usage analysis

There are two rules which can be used for analyzing the memory usage of
a build.

**ram_usage** will show the names of the variables in ram together with
their size sorted in descending size order

**obj_info** will show the flash and RAM memory usage for each
individual object file. The different portions of the RAM usage will
also be shown. A listing is produced with columns for the different
values. The listing is formatted by space separated constant width
fields but this can be changed to tab separated instead by defining the
variable OBJ_INFO_FORM to 1. The listing is by default sorted by
descending RAM values but this can be also be changed by defining the
variable OBJ_INFO_SORT to a value between 0 and 4.

#### Operating system specifics

makeEspArduino is intended to work completely on all the operating
systems specified above. All the required specific setting for the
actual operating system is stored in separate makefiles in the sub
director **/os**.

Please note that Cygwin has some special considerations as most executed
commands expect Windows notations, e.g. COMx for serial port
specification. All paths should also be given in the forward slash
format.

If your project has additional specific requirements you can add them
under conditional statements of **\$(OS)** in your project makefiles
