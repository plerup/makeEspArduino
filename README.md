# makeEspArduino
A makefile for ESP8266 and ESP32 Arduino projects.

The main intent for this project is to provide a minimalistic yet powerful and easy configurable
makefile for projects using the ESP/Arduino framework available at: https://github.com/esp8266/Arduino and https://github.com/espressif/arduino-esp32

Using make instead of the Arduino IDE makes it easier to do more production oriented builds of software projects.

This makefile basically gives you a command line tool for easy building and loading of the ESP/Arduino examples as
well as your own projects.

The makefile can use the ESP/Arduino environment either from the installation within the Arduino IDE or in a separate git clone of the environment. The latter can be useful in project where you want stringent control of the environment version e.g. by using it as a git submodule.

You basically just have to specify your main sketch file and the libraries it uses. The libraries can be from arbitrary
directories without any required specific hierarchy or any of the other restrictions which normally apply to builds made from within the Arduino IDE. The makefile will find all involved header and source files automatically.

Rules for building the firmware as well as upload it to the ESP board are provided.

It is also possible to let the makefile generate and upload a complete flash file system based on an arbitrary directory of files.

The intention is to use the makefile as is. Possible specific configuration is done via via makefile variables supplied on the command line or in separate companion makefiles.

The makefile can be used on Linux, Mac OS and Microsoft Windows (Cygwin or WSL).

The actual build commands (compile, link etc.) are extracted from the Arduino description files (platform.txt etc.).

Uploading of the built binary can be made via serial channel (esptool), ota (espota.py) or http (curl). Which method to use is controlled by makefile target selection. By default the serial channel is used.

Configuration files for Visual Studio Code can be generated by this makefile as well.


#### Installing

First make sure that you have the environment installed as described at:  https://github.com/esp8266/Arduino and https://github.com/espressif/arduino-esp32<br>
If you don't want to use the environment installed in the Arduino IDE, then you can to clone it into a separate
directory instead, see below.

Then start cloning the makeEspArduino repository.

    cd ~
    git clone https://github.com/plerup/makeEspArduino.git

After this you can test it. Attach your ESP8266 board and execute the following commands:

    cd makeEspArduino
    make -f makeEspArduino.mk DEMO=1 flash

The DEMO definition makes the the makefile choose a typical demo sketch from the ESP examples.
After this you will have the example downloaded onto in your ESP.

If you want to use a clone of the environment instead then do something like this for esp8266:

    cd ~
    git clone https://github.com/esp8266/Arduino.git esp8266
    cd esp8266

Determine which version you want to use. [See releases.](https://github.com/esp8266/Arduino/releases) Example:

    git checkout tags/2.6.3

Then install the required environment tools by issuing the following commands:

    git submodule update --init
    cd tools
    python get.py

Please note that you have to rerun the commands above if you checkout another label or branch in the git.

To test this installation you have to specify the location of the environment when running make

    cd ~/makeEspArduino
    make -f makeEspArduino.mk ESP_ROOT=~/esp8266 DEMO=1 flash

For ESP32 just change esp8266 in the commands above to esp32, i.e:

    cd ~
    git clone https://github.com/espressif/arduino-esp32.git  esp32
    cd esp32
    git submodule update --init
    cd tools
    python get.py

When building ESP32 projects the variable CHIP must always be defined, example:

    make -f makeEspArduino.mk ESP_ROOT=~/esp32 CHIP=esp32 DEMO=1 flash

If you want to minimize your typing henceforth then there is a rule in that makefile which can be used to generate shortcut commands in /usr/local/bin. These commands are named **espmake** and **espmake32**. To achieve this when using a git clone type:

    make -f makeEspArduino.mk ESP_ROOT=~/esp8266 install

    make -f makeEspArduino.mk ESP_ROOT=~/esp32 CHIP=esp32 install

Sudo access will be required for this operation.

#### Getting help

A description of all available makefile functions and variables is always available via the following command:

    make -f makeEspArduino.mk help

#### Building projects

You can now use the makefile to build your own sketches or any of the examples in the ESP/Arduino environment. The makefile will automatically search for a sketch in the current directory and build it if found. It is also possible to specify the location of the sketch on the command line.

##### Some examples

In current directory:

    cd ~/.arduino15/packages/esp8266/hardware/esp8266/2.3.0/libraries/Ticker/examples/TickerBasic
    espmake

Explicit naming of a default directory:

    espmake -C ~/.arduino15/packages/esp8266/hardware/esp8266/2.3.0/libraries/Ticker/examples/TickerBasic

Explicit naming of the sketch:

    espmake SKETCH=~/.arduino15/packages/esp8266/hardware/esp8266/2.3.0/libraries/Ticker/examples/TickerBasic/TickerBasic.ino
    # Or like this
    espmake SKETCH="\$(ESP_ROOT)/libraries/Ticker/examples/TickerBasic/TickerBasic.ino"

#### Advanced usage

The makefile has several variables which control the build. There are different ways to change the defaults of these variables.

The simplest and most direct way to do this is by specifying the variables and their values on the command line.

The more permanent way is to create a special makefile with the appropriate values for the variables and then include this in the build. This can be achieved
either by including makeEspArduino.mk in this file or the other way around by letting makeEspArduino.mk include it. The advantage with the latter method is that
the makefile doesn't need to know the location of makeEspArduino.mk, more about this in the examples below.

The most important variables in the makefile are listed below:

**SKETCH** is the path to the main source file. As stated above, if this is missing then makeEspArduino will try to locate it in the current directory.

**LIBS** is a variable which can contain a list of explicit source files and/or directories with multiple source files, which are to be compiled and used as libraries
in the build. Please note that there is no restrictions regarding location and naming of these files as in the Arduino IDE build system.
If you want to achieve automatic search for libraries leave this variable undefined. In this case makeEspArduino will try to recursively locate all required libraries by parsing the include statements in the sketch source file (and other source files in the sketch directory). Libraries in the ESP/Arduino library structure and the standard Arduino library tree will be searched. It is also possible to add other directories/file to search by defining the variable **CUSTOM_LIBS**.

Source files (.S, .c, .cpp) and libraries (.a) are valid to specify here either direct with a full file path or in wildcard via a directory name.

Please note though that if you want stringent version controlled builds, then define **LIBS** yourself and set it to version controlled directories/files.
All source files located in the same directory as the sketch will also be included automatically. The variable **EXCLUDE_DIRS** can be setup to exclude one or several directories from the wildcard search.

**CHIP** Set to either esp8266 (default) or esp32

**BOARD** The type of ESP8266 or ESP32 board you are using

**BUILD_DIR** All intermediate build files (object, map files etc.) are stored in a separate directory controlled by this variable. By default this is set to a name consisting of the project and board names. This is just the directory name, the root of this directory is controlled by the variable **BUILD_ROOT**. Default for this is /tmp/mkESP but it can be set to a non-temporary location if so is desired.

**BUILD_EXTRA_FLAGS** this variable can be setup to add additional parameters for the compilation commands. It will be placed last and thereby it is possible to override the preceding default ones.

There are some other important variables which corresponds to the settings which you normally do in the "Tools" menu in the Arduino IDE. The makefile will parse the Arduino IDE configuration files and use the same defaults as you would get when after selecting a board in the "Tools" menu.

The result of the parsing is stored as variables in a separate intermediate makefile named 'arduino.mk' in the directory defined by the variable BUILD_DIR. Look into this file if you need to control even more detailed settings variables.

As stated above you can always get a description of all makefile operations, configuration variables and their default values via the 'help' function

    espmake help

##### Build time and version information

makeESPArduino will also automatically produce header and c files which contain information about the time when the build (link)
was performed. This file also includes the git descriptions (tag) of the used version of the ESP/Arduino environment and the project source (when applicable).
This can be used by the project source files to provide stringent version information from within the software. The information is put into a global struct
variable named "_BuildInfo" with the following string constant fields:

| Name        | Value |
| ----------- |-------------|
| __src_version__ | Source code git version |
| __date__ | Build date |
| __time__ | Build time |
| __env_version__ | ESP Arduino version |


##### Including the makefile

The easiest way to control the makefile is by defining the desired values of the control variables in your own makefile and then include makeEspArduino.mk. Example:


    # My makefile
    SKETCH = $(ESP_ROOT)/libraries/Ticker/examples/TickerBasic/TickerBasic.ino

    UPLOAD_PORT = /dev/ttyUSB1
    BOARD = esp210

    include $(HOME)/makeEspArduino/makeEspArduino.mk

Another possibility is to do this the other way around, i.e. let makeEspArduino include your makefile instead. This can be achieved by naming
your makefile "config.mk". makeEspArduino will always check for a file with this name in the current directory or in the same directory as the sketch.
If you want to use another name for your makefile you can specify this via the variable PROJ_CONF on the command line. Example of such a makefile:

    # config.mk
    THIS_DIR := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
    ROOT := $(THIS_DIR)/..
    LIBS = $(ESP_LIBS)/SPI \
      $(ESP_LIBS)/Wire \
      $(ESP_LIBS)/ESP8266WiFi \
      $(ROOT)/libraries \
      $(ROOT)/ext_lib

    UPLOAD_SPEED = 115200

It is of course also always possible to control the variable values in the makefile by defining them as environment variables in the shell. Example:

    export UPLOAD_PORT=/dev/ttyUSB2

A global config file which will apply to all builds can also be defined. The name of this file is also "config.mk". The location of this file can be defined via the variable **MAKEESPARDUINO_CONFIGS_ROOT** The default value is the OS specific standard config directory, i.e.

    Linux:  $(HOME)/.config/makeEspArduino (or $(XDG_CONFIG_HOME)/makeEspArduino)
    Mac:    $(HOME)/Library/makeEspArduino
    CygWin: $(LOCALAPPDATA)/makeEspArduino

PLease note that the local config file can always override definitions in the global one.


#### Flash operations for esp8266

Some of the flashing operations in makeEspArduino require the "esptool" Python program. This is bundled automatically for esp32/Arduino but for esp8266 the handling of this has changed a lot during the different releases of esp8266/Arduino. To cope with this makeEspArduino require you to have this installed separately in the affected cases. This can be done from: https://github.com/espressif/esptool or just by typing:

    pip install esptool

If it is missing when required, an error message will be shown.

#### Building a file system

There are also rules in the makefile which can be used for building and uploading a complete flash file system to the ESP. This is basically the same functionality
as the one available in the Arduino IDE, https://github.com/esp8266/Arduino/blob/master/doc/filesystem.rst#uploading-files-to-file-system

Both SPIFFS and LittleFS file systems are supported and which type to use is specified via the **FS_TYPE** variable.

The size and flash location parameters are taken from boards.txt for esp8266 and from the partition table for esp32.

The file system content is made up of everything within a directory specified via the variable **FS_DIR**. By default this variable is set to a subdirectory named **data** in the sketch directory.

Use the rule **flash_fs** or **ota_fs** to generate a file system image and upload it to the ESP.

All the settings for the file system are taken from the selected board's configuration.

It is also possible to dump and recreate the complete file system from the device via the rule **dump_fs**. The corresponding flash section will be extracted and the individual files recreated in a directory in the build structure.


#### Additional flash I/O operations

The makefile has rules for dumping and restoring the whole flash memory contents to and from a file. This can be convenient for saving a specific state or software for which no source code is available.

For esp8266, this functionality requires that "esptool.py" is available as specified above.

The rules are named **dump_flash** and **restore_flash**. The name of the output/input file is controlled by the variable **FLASH_FILE**. The default value for this is "esp_flash.bin". All required parameters for the operations are taken from the variables mentioned above for flash size, serial port and speed etc.

Example:

    espmake dump_flash FLASH_FILE=my_flash.bin


#### Building an object file library

It is also possible to build a library containing all the object files referenced in the build (excluding the sketch itself). This can e.g. be used to build separately compiled version controlled libraries which are then used in other build projects.

Example:

    espmake lib


#### Misc build features

##### Using ccache

If you want to speed up your builds with makeEspArduino and have ccache available on your platform, this can easily be enabled. Just set the variable **USE_CCACHE** to 1 and all C and C++ compilations will be prefixed with ccache.

##### Cross compilation

If you want some other prefix to the C compiler command line the following variables are available: **C_COM_PREFIX** and **CPP_COM_PREFIX**

##### Parallel builds

You can limit the number of compilation threads started by setting the **BUILD_THREADS** variable to the desired number.

##### Automatic rebuild

A record of the command line parameters and git versions used in the last build is stored in the build directory. If any of these are changed during the next build, e.g. changing a variable definition, a complete rebuild is made in order to ensure that all possible changes are applied. If you don't want this function just define the variable **IGNORE_STATE**.

##### Intermediate object archive

By default all object files are put into an archive as this seems to enable the linker to remove 5 kB RAM of unused variables. This is the same method as is used by the Arduino IDE. Onfortunatly this might break some builds i.g. if some special linker flags are used. To disable this feature set the **NO_USER_OBJ_LIB** to 1.


#### User defined make rules

makeEspArduino has make rules for all the type of input files that are normally part of a build of Arduino for esp. If you want to add other type of files there are two variables which can be used for this purpose.

**USER_SRC_PATTERN** Files matching this pattern will be included in the automatic search for source files. Must be prefixed with a "|". Example:

    USER_SRC_PATTERN = |my_ext

**USER_RULES** This variable is used to define the path to a makefile which contains the actual make rules for the user specific source files. Example of contents for such a file:

    $(BUILD_DIR)/%.my_ext.o: %.my_ext
      echo Running my make rule for $<
      my_command $<

#### Setting used version of ESP Arduino

The rule **set_git_version** can be used to control which version tag to be used in the git repo specified via **ESP_ROOT**. It will perform the necessary git and copy operations to ensure that the repo is setup correctly for the tag specified via the variable **REQ_GIT_VERSION**. Example:

    espmake set_git_version REQ_GIT_VERSION=2.6.3


#### Using Visual Studio Code

Visual Studio Code is a great editor which can be used together with makeEspArduino. The makefile contains a rule named "vscode". When invoked it will generate a config file for the C/C++ addin. This will contain all the required definitions for the IntelliSense function. The information is based on the parameters of the c/c++ compilation command.

It will also generate contents in the "tasks" configuration file which enables building with makeEspArduino from within the editor. This is convenient for stepping through compilation errors for instance.

The configuration files will have settings with the name of the main sketch.

The workspace directory for the settings files will be ".vscode" and this can either be automatically detected by makeEspArduino or be specified via the variable **VS_CODE_DIR**. Automatic here means checking the parent directories of the sketch for a config directory and if doesn't exist then the sketch directory itself will be used and created if not found. If an existing project file (*.code-workspace) is found in that directory it will be used as input for the launch of VS Code.

After generating the configuration files makeEspArduino will launch Visual Studio (if available in the path)

#### Crash analysis

The rule **crash** will enable you to paste the output of a program crash for esp8266 or esp32. Explanatory reason and call stack traceback will be listed with source file and line number for each call found.
