# makeEspArduino
A makefile for ESP8266 Arduino projects.

The main intent with this is to provide a minimalistic yet powerful and easy configurable
makefile for projects using the ESP8266 Arduino framework available at: https://github.com/esp8266/Arduino

Using make instead of the Arduino IDE makes it easier to do more production oriented builds of software projects.

You basically just have to specify your main sketch file and the libraries it uses. The libraries can be from arbitrary
directories without any required specific hierarchy. The makefile will find all involved header and source files automatically.

The makefile will also automatically produce header and c files which contains information about the time when the build (link)
was performed. This file also includes the git descriptions (tag) of the used version of the ESP8266/Arduino environment and the project source.
This can be used by the project source files to provide stringent version information.

Rules for building the firmware as well as upload to the ESP8266 are provided.

Edit the contents of the makefile file to suit your project or just include it as it is and override the applicable macros.
It is of course also possible to control the makefile from the make command line.

The makefile is designed for GNU make and Linux, may work on CygWin as well.

Staring from version 2.0, all the actual build commands are extracted from the Arduino description files (platform.txt etc.). 

## How to use:

First make sure that you have a copy of the ESP8266/Arduino repository and the needed tools.
Example:

    cd ~
    git clone https://github.com/esp8266/Arduino.git
    mv Arduino esp8266
    cd esp8266/tools
    python get.py

Determine which version you want to use. [See releases](https://github.com/esp8266/Arduino/releases) Example:

    git checkout tags/2.2.0

Clone this repository.

    cd ~
    git clone https://github.com/plerup/makeEspArduino.git
    cd makeEspArduino
    make -f makeEspArduino.mk upload

After this you will have the example "HelloServer" in your ESP.

### Command line usage

You can also control the makefile by defining variables on the command line which starts make, for example:

    make -f makeEspArduino.mk upload SKETCH=~/esp8266/libraries/Ticker/examples/TickerBasic/TickerBasic.ino LIBS=~/esp8266/libraries/Ticker


### Including the makefile

Instead of modifying the makefile you can include it as is from your own makefile and then by defining the control variables here you can override the defaults, example:

    # My makefile
    SKETCH = $(ESP_ROOT)/libraries/Ticker/examples/TickerBasic/TickerBasic.ino
    LIBS = $(ESP_ROOT)/libraries/Ticker
    
    UPLOAD_PORT = /dev/ttyUSB1
    BOARD = esp210
    
    -include ~/makeEspArduino/makeEspArduino.mk
    

### Advanced options

The makefile contains some variables which control more advanced build options.

| Variable  | Function |
| :------------- | :------------- |
| **VERBOSE**  | By default the build process runs in silent mode, i.e. the commands are not echoed.<br>Set this variable to 1 in order to change this.  |
| **SINGLE_THREAD**  | The build is by default using multiple threads for parallel operations.<br>This variable can be set to 1 in order to force single threaded builds.  |
| **USE_PREBUILD**  | Later versions of ESP8266 Arduino has pre-build operations which creates a header file for git information. As makeESPArduino already has this function this is not enabled by default. Mainly because it will trigger unnecessary builds.<br>If you do want this function here as well set this variable to 1.  |


