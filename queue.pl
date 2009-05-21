#!/usr/bin/perl

# Add, View, Execute, Delete jobs in queue

use warnings;
use strict;
use YAML::Syck;

my @list = (
  {
    description => "Theoder=>theodor4-1.mp4, t=4, c=1",
    input => "~/Desktop/ISO/Thomas og Snelokomotivet",
    output => "tmp/theodor4-1.mp4",
    progress => "done",
  },
  {
    description => "Theoder=>theodor5-1.mp4, t=5, c=1",
    input => "~/Desktop/ISO/Thomas og Snelokomotivet",
    output => "tmp/theodor5-1.mp4",
    progress => "todo",
  },
);

print Dump \@list;
