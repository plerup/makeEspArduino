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
