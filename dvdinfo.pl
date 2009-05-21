#!/usr/bin/perl -l

# Read Title, Chapter, Lang, Resolution Information, etc from DVD
# XXX TODO
#  - NTSC/telecine detect
#  - Skip too short titles earlier
#  - Recommend language

use warnings;
use strict;

our $scandvd = 'mplayer -identify -frames 1 -vo null -ao null -dvd-device';

sub numtitles {
  my $input = shift;

  my $info = qx,$scandvd "$input" dvd:// 2>/dev/null,;
  #warn "info: $info";

  my($numtitles) = $info =~ /ID_DVD_TITLES=(\d+)/;
  return $numtitles;
}

sub cropdetect {
  my($input,$title) = @_;

  #my $cropdetect = qx,mplayer -nosound -vo null -benchmark -vf cropdetect -ss 60 -frames 500 -dvd-device "$input" dvd://$title 2>/dev/null | grep CROP | tail -n1 | cut -d= -f2 | cut -d\) -f1,;
  my $cropline;
  open CROP, qq,mplayer -nosound -vo null -benchmark -vf cropdetect=80 -ss 60 -frames 500 -dvd-device "$input" dvd://$title 2>/dev/null |,;
    while(<CROP>){
      #print;
      next unless /CROP/;
      chomp;
      $cropline = $_;
    }
  close CROP;
  return '' unless $cropline;
  $cropline =~ /crop=([\d\:]+)/ and my $cropdetect = $1;
  return $cropdetect;
}
 
# 720x480 854x480 704:464:10:6
# -> 
sub resize {
  my($input,$display,$crop) = @_;

  my($xi,$yi) = split 'x', $input;
  my($xd,$yd) = split 'x', $display;
  my($xc,$yc) = split ':', $crop;
  $xc ||= $xi;
  $yc ||= $yi;

  my $xr = $xd * $xc / $xi;         # 854 * 704 / 720 => 835
  my $yr = $yd * $yc / $yi;         # 480 * 464 / 480 => 464
  my($xo,$yo,$b);
  if ( $xr/$yr > 1.5 ) {
    # Too wide
    $xo = 720;
    $yo = int ( 720 / $xr * $yr );  # 720 / 835 * 464 => 400
    $b = $yo / 480;                 # 400 / 480 => 83%
  } else {
    # Too tall
    $xo = int ( 480 / $yr * $xr );  # 480 / 464 * 835 => 863
    $yo = 480;
    $b = $xo / 720;                 # 863 / 720 => 120 %
  }
  return ( $xo, $yo, $b );
}

sub printout {
  print join "\t", @_;
}

sub titleinfo {
  my($input,$title) = @_;

  my $info = qx,$scandvd "$input" dvd://$title 2>/dev/null,;
  my @lang = $info =~ /ID_AID_\d+_LANG=(\w+)/g;
  my @subt = $info =~ /ID_SID_\d+_LANG=(\w+)/g;
  my($chapters) = $info =~ /CHAPTERS: (\S+),/;
  $chapters ||= '';
  my @c = split ',', $chapters;
  $chapters = scalar @c;
  my($length) = $info =~ /ID_LENGTH=(\S+)/;
  my($resin,$resout) = $info =~ /VO: \[null\] (\d+x\d+) => (\d+x\d+)/;
  my $crop = cropdetect($input,$title);
  my @resize = resize($resin, $resout, $crop);
  #warn "resize: @resize\n";
  return 
    $title,
    $length,
    $chapters,
    $resin,
    $resout,
    $crop,
    sprintf("%dx%d",@resize),
    sprintf("%.1f%%", 100 * $resize[2]),
    join(',',@lang),
    join(',',@subt),
    ;
}

my $titles = numtitles $ARGV[0];
printout "#title", "length", "#chap", qw(resin resout crop resize cover audio subtitle);
for my $t ( 1 .. $titles ) {
  my @info = titleinfo($ARGV[0], $t);
  next if $info[1] < 60;
  my $min = sprintf "%d:%02d", int($info[1]/60), int($info[1]%60);
  $info[1] = $min;
  printout @info;
}

