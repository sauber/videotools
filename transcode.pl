#!/usr/bin/perl

# Transcode from one video format to another
#  - Read Video
#  - Read Audio
#  - Read subtitle
#  - Video filters: deinterlace, deblock, crop, resize, pad
#  - Audio filters: normalize
#  - Subtitle filters: -
#  - Write Container

# Use mencoder to
#  - Read DVD FS
#  - Deinterlace, deblock
#  - Resize
#  - Apply subtitles
#  - Sample or full length

# Use ffmpeg to 
#  - Encode with x264
#  - Two pass
#  - Generate PSP format container

use warnings;
use strict;
use Getopt::Long;


########################################################################
### Reading
########################################################################

# Move subtitles to a temporary file
#
sub dumpsub {
}

########################################################################
### MAIN
########################################################################

sub usage {
  <<EOF;
usage: $0 [options] infile outfile

Options:
-help         show help
-sample secs  generate random sample
EOF
}

# Arguments
our $dvdtitle = 1;
our $dvdchapters;
our $dvddevice;
our $sample = 10;
our $help;

GetOptions(
  "dvdtitle=i"    => \$dvdtitle,     # Integer
  "dvdchapters=s" => \$dvdchapters,  # String
  "dvddevice=s"   => \$dvddevice,    # String
  "sample:i"      => \$sample,       # Optional Integer
  "help|?"        => \$help,         # Flag
)

