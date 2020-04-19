#!/usr/bin/env perl
#====================================================================================
# find_inc.pl
#
# Find directories with header files used by the source files
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
use File::Find;

my @dirs = split(" ", shift);
my %files;

# Search for include statements in the supplied source files
while (<>) {
  $files{"$1"} = 1 if /^\s*\#include\s+[<"]([^>"]+)/;
}

# Recursive search for the found include files in the specified directories
find(
  sub {
    if ($files{$_}) {
      print $File::Find::dir, " ";
      $files{$_} = 0;
    }
  },
  @dirs);