#!/usr/bin/env perl

# Script to extract rtmp links from DR NU pages.
# Input, first argument to script, is DR NU page where videois featured.
# Output, stdout, is the rtmp link to the video of highest resolution and
# example arguments for rtmpdump command.
# Soren, Aug 2012

use warnings;
use strict;
use WWW::Mechanize;
use JSON;

my $nupage = $ARGV[0];

our $mech = WWW::Mechanize->new();
$mech->get( $nupage );
my $content = $mech->content;

$content =~ /resource: "(.*?)",/ and my $resource = $1;
$mech->get( $resource );
$content = $mech->content;
my $dataref = decode_json $content;
my @resolutions =
  sort { $b->{bitrateKbps} <=> $a->{bitrateKbps} }
  @{ $dataref->{links} };
my $uri = $resolutions[0]{uri}; # Highest bitrate
$uri =~ s/cms/cms\/cms/;

print "rtmpdump -r '$uri' > filename.mp4\n";
