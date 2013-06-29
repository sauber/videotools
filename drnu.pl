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
use YAML::Syck;

my $nupage = $ARGV[0];

our $mech = WWW::Mechanize->new();
$mech->get( $nupage );
my $content = $mech->content;

$content =~ /resource: "(.*?)",/ and my $resource = $1;
$mech->get( $resource );
$content = $mech->content;
my $dataref = decode_json $content;
my $filename =  $dataref->{Data}[0]{Slug} . ".mp4";
print "*** filename: $filename\n";
my $links = $dataref->{Data}[0]{Assets}[0]{Links};
my @resolutions =
  sort { $b->{Bitrate} <=> $a->{Bitrate} }
  grep { $_->{Uri} =~ /^(rtmp)/ }
  @$links;
my $uri = $resolutions[0]{Uri}; # Highest bitrate
print "*** uri: $uri\n";
if ( $uri =~ /^http/ ) {
  system "mplayer -dumpstream -playlist '$uri'";
} elsif ( $uri =~ /^rtmp/ ) {
  #system "rtmpdump ry '$uri' -o '$filename'";
  my $rtmp_url = $uri;
  $rtmp_url=~s!rtmp://vod.dr.dk/cms\/mp4:!mp4:!;
  system "rtmpdump -r \"rtmp://vod.dr.dk/cms\" -a \"cms\" -y \"$rtmp_url\" -o \"$filename\" ";
} else {
  print "Unknown uri\n";
}
