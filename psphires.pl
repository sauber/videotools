#!/usr/bin/perl

# Generate PSP formatted mp4 files
# Soren, 2009-04-06
# Filters:
#   - Deinterlate
#   - Deblock
#   - Stretch to square pixels
#   - Scale to 720/480
#   - Black padding
#   - Video bitrate 1400
#   - XXX: MP4/psp formatted output
#   - XXX: Audio
#   - XXX: Preview


sub videoinfo {
  my $inputfile = shift;
  our $identify;
  unless ( $identify ) {
    $identify = qx,ffmpeg -i $inputfile 2>&1,;
  }
  return $identify;
}

# Read Input Resolution, Pixel Aspect and Display Aspect
# Calculate Display resolution
#
sub displayres {
  my $input = shift;

  my $info = videoinfo($input);
  ( my $stream = $info ) =~ s/.*(Stream.*?Video.*?)[\r\n].*/$1/s;
  my($xi,$yi,$xp,$yp,$xd,$yd,$xo,$yo);
  $stream =~ /, (\d+)x(\d+)/     and do { $xi = $1; $yi = $2 };
  $stream =~ /PAR (\d+):(\d+)/ and do { $xp = $1; $yp = $2 };
  $stream =~ /DAR (\d+):(\d+)/ and do { $xd = $1; $yd = $2 };
  if ( $xp and $yp ) {
    my $par = $xp/$yp;
    if ( $par == 1 ) {
      $xo = $xi;      $yo = $yi;
    } elsif ( $par > 1 ) {
      $xo = $xi*$par;      $yo = $yi;
    } else {
      $xo = $xi; $yo = $yi/$par;
    }
  } else {
      $xo = $xi;      $yo = $yi;
  }
  warn "# Input resolution: ${xi}x${yi}\n";
  warn "# Input aspect: ${xp}:${yp}\n";
  warn "# Display resolution: ${xo}x${yo}\n";
  return ($xo, $yo);
}

sub scaledres {
  my $input = shift;
  my($xd,$yd) = displayres($input);

  my($xs,$ys);
  my $r = $xd/$yd;
  if ( $r > 720/480 ) {
    $xs = 720; $ys = 720/$r;
  } else {
    $xs = 480*$r; $ys = 480;
  }
  warn "# PSP resolution: ${xs}x${ys}\n";
  return ($xs,$ys);
}

# Padding. Must be even numbers!
sub padding {
  my $input = shift;
  my($xs,$ys) = scaledres($input);

  my $xb = $yb = 0;
  $xb = 2 * int((720-$xs)/4);
  $yb = 2 * int((480-$ys)/4);
  warn "# Horizontal Padding: 2x$xb\n";
  warn "# Vertical Padding: 2x$yb\n";
  return ($xb,$yb);
}

sub pspresize {
  my $input = shift;
  my($xb,$yb) = padding($input);

  my $w = 720 - $xb*2;
  my $h = 480 - $yb*2;
  my $opt = "-s ${w}x${h} -aspect " . 720/480 . " -b 1400k";
  $opt .= " -padleft $xb -padright $xb" if $xb > 0;
  $opt .= " -padtop $yb -padbottom $yb" if $yb > 0;
  warn "# ffmpeg resize: $opt\n";
  return $opt;
}

sub inputfile {
  my($input) = @_;

  my $opt = "$input";
  warn "# input file: $opt\n";
  return $opt;
}

sub outputfile {
  my($output) = @_;

  my $opt = "-o $output";
  warn "# output file: $opt\n";
  return $opt;
}

sub videocodec {
  #my $opt = "-vcodec mpeg4 -f psp -g 300";
  #my $opt = "-vcodec libx264 -f psp -g 300";
  #my $opt = "-vcodec libx264";
  my $opt = "-ovc lavc -lavcopts vcodec=libx264";
  #my $opt = "-ovc libx264";
  warn "# codec: $opt\n";
  return $opt;
}

sub prefilters {
  #my $opt = "-deinterlace";
  my $opt = "-vf-add filmdint";
  warn "# prefilters: $opt\n";
  return $opt;
}

sub postfilters {
  #my $opt = "-y -aic 2 -mbd 2 -cmp 3 -precmp 3 -subcmp 3 -trellis 2 -flags +4mv+trell";
  #my $opt = "-y -mbd 2 -cmp 3 -precmp 3 -subcmp 3 -trellis 2";
  my $opt = "-vpre hq -vpre main -level 30 -refs 2 -b 1400k -bt 1400k -threads 0";
  warn "# ffmpeg postfilters: $opt\n";
  return $opt;
}

sub audio {
  #my $opt = "-acodec libfaac";
  #my $opt = "-acodec libfaac -ac 2 -ab 128k -ar 48000";
  my $opt = "-oac lavc";
  warn "# audio: $opt\n";
  return $opt;
}

sub ffmpegargs {
  my($input,$output) = @_;

  return join " ", 
    "mencoder",
    audio(),
    #pspresize($input),
    videocodec(),
    prefilters(),
    #postfilters($input),
    outputfile($output),
    inputfile($input),
    "\n";
}


sub usage {
  die <<EOF;
$0: <filename>
EOF
}

usage unless $ARGV[0];
die "cannot read $ARGV[0]\n" unless -r $ARGV[0];
#pspresize $ARGV[0];
if ( $ARGV[1] ) {
  print ffmpegargs(@ARGV);
} else {
  pspresize(@ARGV);
}
