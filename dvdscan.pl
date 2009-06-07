#!/usr/bin/perl

# Read Title, Chapter, Lang, Resolution Information, etc from DVD
# XXX TODO
#  - NTSC/telecine detect
#  - Go back to previous menu
#  - -auto mode for no menus
#  - Help page to explain syntax for options
#  - Aspect needs to be 16/9 even though psp screen is 3:2
#
#  Add a interactive flow
#   0 Basic Scan DVD
#   0 Remove too Short titles
#   0 Interactive remove titles, offer preview
#   0 Detect crop, offer preview
#   0 Audio language
#   0 Subtitle language
#   0 Confirm
#   0 Write batch files

use warnings;
use strict;
use Term::Prompt;

our $scandvd = 'mplayer -identify -frames 1 -vo null -ao null -dvd-device';
our %dvd;

# Dump a data sctructure
#
sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["dump $_[0]"]);
}

########################################################################
### Extract Data from Media Source
########################################################################

# Read Titles and Chapters from DVD. Autoselect titles > 2min length
# Example output from mplayer
#   ID_DVD_TITLE_1_CHAPTERS=33
#   ID_DVD_TITLE_1_ANGLES=1
#   ID_DVD_TITLE_1_LENGTH=5524.900
#
sub dvdtitlescan {
  my $input = shift;

  $dvd{src} = $input;
  my $dir = $input;
  $dir =~ s/\/$//;  # Remove trailing slash
  $dvd{batch} = "$dir.batch.sh";
  $dir =~ s/^.*\///;  # Remove path
  $dvd{dir} = $dir;
  $dvd{folder} = "/Users/sauber/Desktop/PSP/$dir";
  open SCAN, qq,$scandvd "$input" dvd:// 2>/dev/null |,;
    while (<SCAN>) {
      /ID_DVD_TITLE_(\d+)_CHAPTERS=(\d+)/ and $dvd{title}{$1}{chapters} = $2;
      /ID_DVD_TITLE_(\d+)_LENGTH=([\d\.]+)/ and do {
        $dvd{title}{$1}{length} = $2;
        $dvd{title}{$1}{selected} = 1 if $2 >= 120;
      };
    }
  close SCAN;
}

# Read information about a Title
#  - Audio Language
#  - Subtitle languages
#  - Resolutions
#  - FPS
# 
sub dvdtitleinfo {
  my $title = shift;

  #warn "Getting lang, res for title $title\n";
  my $info = qx,$scandvd "$dvd{src}" dvd://$title 2>/dev/null,;
  my @lang = $info =~ /ID_AID_\d+_LANG=(\w+)/g;
  my @subt = $info =~ /ID_SID_\d+_LANG=(\w+)/g;
  my($chapters) = $info =~ /CHAPTERS: (\S+),/;
  $chapters ||= '';
  my @c = split ',', $chapters;
  $chapters = scalar @c;
  my($length) = $info =~ /ID_LENGTH=(\S+)/;
  my($resin,$resout) = $info =~ /VO: \[null\] (\d+x\d+) => (\d+x\d+)/;
  #my $crop = cropdetect($input,$title);
  #my @resize = resize($resin, $resout, $crop);
  #warn "resize: @resize\n";
  #return 
  #  $title,
  #  $length,
  #  $chapters,
  #  $resin,
  #  $resout,
  #  $crop,
  #  sprintf("%dx%d",@resize),
  #  sprintf("%.1f%%", 100 * $resize[2]),
  #  join(',',@lang),
  #  join(',',@subt),
  #  ;
  my %U;
  # XXX: Bunch of defaults here. Get user preferences somewhere else
  $dvd{title}{$title}{audiolang} = [ grep { !$U{$_}++ } @lang ];
  %U = ();
  $dvd{title}{$title}{subtitle}  = [ grep { !$U{$_}++ } @subt ];
  $dvd{title}{$title}{videoresolution} = $resin;
  $dvd{title}{$title}{displayresolution} = $resout;
  $dvd{title}{$title}{sample} = '25-75';
  $dvd{title}{$title}{file} = sprintf "%s-%02d.mp4", $dvd{dir}, $title;
  resize($title);
  langselect($title);
  #x "title $title", $dvd{title}{$title};
}

# Automatically detect cropping
#
sub cropdetect {
  #my($input,$title) = @_;
  my $title = shift;

  #my $cropdetect = qx,mplayer -nosound -vo null -benchmark -vf cropdetect -ss 60 -frames 500 -dvd-device "$input" dvd://$title 2>/dev/null | grep CROP | tail -n1 | cut -d= -f2 | cut -d\) -f1,;
  my $cropline;
  my($start,$end) = split '-', $dvd{title}{$title}{sample};
  $end -= $start;
  my $cmd = sprintf 'mplayer -nosound -vo null -benchmark -vf cropdetect -ss %d -endpos %d -dvd-device "%s" dvd://%d 2>/dev/null',
    $start, $end, $dvd{src}, $title;
  #open CROP, qq,mplayer -nosound -vo null -benchmark -vf cropdetect=80 -ss 60 -frames 500 -dvd-device "$input" dvd://$title 2>/dev/null |,;
  open CROP, qq,$cmd |,;
    while(<CROP>){
      #print;
      next unless /CROP/;
      chomp;
      $cropline = $_;
    }
  close CROP;
  if ( $cropline ) {
    $cropline =~ /crop=([\d\:]+)/ and my $cropdetect = $1;
    $dvd{title}{$title}{crop} = $cropdetect;
  } else {
    $dvd{title}{$title}{crop} = $dvd{title}{$title}{videoresolution};
  }
  #return $cropdetect;
  resize($title);
}



########################################################################
### Writing Batch Scripts
########################################################################

# Write batch script to convert media
#
sub writebatch {
  open BATCH, ">$dvd{batch}";
    print BATCH <<EOF;

# Create destination folder
mkdir "$dvd{folder}"
EOF

    for my $title ( selectedtitles() ) {
      # Scaling and languages
      my $alang = $dvd{title}{$title}{selectedaudio}
                ? "-alang $dvd{title}{$title}{selectedaudio}"
                : '' ;
      my $slang = $dvd{title}{$title}{selectedsubtitle}
                ? "-slang $dvd{title}{$title}{selectedsubtitle}"
                : '' ;
      my $resize = $dvd{title}{$title}{selectedsubtitle}
                ? "-slang $dvd{title}{$title}{selectedsubtitle}"
                : '' ;
      my $crop  = $dvd{title}{$title}{crop}
                ? ",crop=$dvd{title}{$title}{crop}"
                : '' ;
         $crop  =~ s/x/:/g;
      my $scale = $dvd{title}{$title}{resize}
                ? ",scale=$dvd{title}{$title}{resize}"
                : '' ;
         $scale =~ s/x/:/g;

      # Check if we should do whole stream, and chapter by chapter
      my $numfiles = $dvd{title}{$title}{eachchapter}
                   ? $dvd{title}{$title}{chapters}
                   : 1;
      for my $stream ( 1 .. $numfiles ) {
        my $dstfile = "$dvd{folder}/$dvd{title}{$title}{file}";
        my $chapters = '';
        if ( $dvd{title}{$title}{eachchapter} ) { 
          $dstfile =~ s/\.(.*?)$/sprintf("-%02d.%s", $stream, $1)/e;
          $chapters = "-chapter $stream-$stream";
        }
        print BATCH convertrecipe(
          crop     => $crop,
          scale    => $scale,
          slang    => $slang,
          alang    => $alang,
          title    => $title,
          srcfile  => $dvd{src},
          dstfile  => $dstfile,
          chapters => $chapters,
        );
      }
    }
  close BATCH;
  print "$dvd{batch} written\n";
}

# Convert one video stream into another.
# Use mencoder for decoding, and ffmpeg to encode.
# ffv1 is a lossless format that both tools understand.
#
sub convertrecipe {
  my %p = @_;

  <<EOF;

# Decode Title $p{title} $p{chapters}
# Apply all filters, scaling, and language options
mencoder \\
  -vf kerndeint$p{crop}$p{scale},expand=720:480,dsize=16/9,pp=al,denoise3d \\
  $p{slang} \\
  $p{alang} -oac lavc -lavcopts acodec=libfaac:aglobal=1 \\
  -af volnorm=1:.99 \\
  -ovc x264 -x264encopts bitrate=1400:global_header:level_idc=30 \\
  -dvd-device "$p{srcfile}" dvd://$p{title} $p{chapters} \\
  -of lavf \\
  -o "$p{dstfile}"

EOF
}

sub old_convertrecipe {
  my %p = @_;

  <<EOF;

# Decode Title $p{title} $p{chapters}
# Apply all filters, scaling, and language options
mencoder \\
  -vf kerndeint$p{crop}$p{scale},expand=720:480,dsize=16/9,pp=al,denoise3d \\
  $p{slang} \\
  $p{alang} -oac pcm -af volnorm \\
  -ovc lavc -lavcopts vcodec=ffv1:aspect=16/9 -ofps 30000/1001 \\
  -dvd-device $p{srcfile} dvd://$p{title} $p{chapters} \\
  -o $p{dstfile}.ffv1

# Encode Title $p{title} $p{chapters}
ffmpeg \\
  -i $p{dstfile}.ffv1 \\
  -acodec libfaac -ac 2 -ab 128k -ar 48000 \\
  -vcodec libx264 -vpre hq -vpre main -refs 2 -b 1400k -bt 1400k -threads 0 \\
  -psnr \\
  -y $p{dstfile}

rm $p{dstfile}.ffv1
EOF
}





########################################################################
### Media Options
########################################################################

# Resize to fit target device. Consider cropping.
# 720x480 854x480 704:464:10:6
# -> 
sub resize {
  #my($input,$display,$crop) = @_;
  my $title = shift;

  $dvd{title}{$title}{crop} ||= $dvd{title}{$title}{videoresolution};
  my($xi,$yi) = split 'x', $dvd{title}{$title}{videoresolution};
  my($xd,$yd) = split 'x', $dvd{title}{$title}{displayresolution};
  my($xc,$yc) = split /[:x]/, $dvd{title}{$title}{crop};

  return unless $xi and $yi;
  #x "resize $title", $dvd{title}{$title};

  my $xr = $xd * $xc / $xi;         # 854 * 704 / 720 => 835
  my $yr = $yd * $yc / $yi;         # 480 * 464 / 480 => 464
  my($xo,$yo,$b);
  #if ( $xr/$yr > 1.5 ) {
  #  # Too wide
  #  $xo = 720;
  #  $yo = int ( 720 / $xr * $yr );  # 720 / 835 * 464 => 400
  #  $b = $yo / 480;                 # 400 / 480 => 83%
  #} else {
  #  # Too tall
  #  $xo = int ( 480 / $yr * $xr );  # 480 / 464 * 835 => 863
  #  $yo = 480;
  #  $b = $xo / 720;                 # 863 / 720 => 120 %
  #}
  my $an = (16/9) / (720/480);  # Anamorphic 1.18518
  if ( $xr/$yr > 16/9 ) {
    # Too wide
    $xo = 720;
    $yo = int ( 720 / $xr * $yr / $an );  # 720 / 835 * 464 / 1.18 => 338
    $b = $yo / 480;                       # 338 / 480 => 70%
  } else {
    # Too tall
    $xo = int ( 480 / $yr * $xr / $an );  # 480 / 464 * 835 / 1.18 => 732
    $yo = 480;
    $b = $xo / 720;                 # 863 / 720 => 120 %
  }
  #return ( $xo, $yo, $b );
  $dvd{title}{$title}{resize} = "${xo}x${yo}";
  $dvd{title}{$title}{padding} = $b;
  $dvd{title}{$title}{anamorphic} = ( $xd / $yd ) / ( $xi / $yi );
  warn sprintf "Resize track $title from %s to %s, Screen Filled: %.1f\n",
    $dvd{title}{$title}{videoresolution},
    $dvd{title}{$title}{resize},
    100*$dvd{title}{$title}{padding};
}


# Manually set crop. Then resize to fix target device
#
sub cropset {
  my($title,$crop) = @_;

  $dvd{title}{$title}{crop} = $crop;
  resize($title);
}

# Togle on/off if each chapter should be encoded seperately
#
sub chaptertogle {
  my $title = shift;

  if ( $dvd{title}{$title}{eachchapter} ) {
    delete $dvd{title}{$title}{eachchapter};
    return;
  }
  $dvd{title}{$title}{eachchapter} = 'yes';
}

# List of titles currently selected
#
sub selectedtitles {
  grep $dvd{title}{$_}{selected}, sort { $a <=> $b } keys %{$dvd{title}};
}


########################################################################
### Previewing
########################################################################

# Previewing cropping by placing a rectangle
#
sub croppreview {
  my $title = shift;

  # Make crop is properly formatted
  my $crop = $dvd{title}{$title}{crop};
  my($w,$h,$x,$y) = split /[x:]/, $crop;
  unless ($x and $y) {
    my($xd,$yd) = split /[x:]/, $dvd{title}{$title}{videoresolution};
    $x ||= 2 * int( ($xd-$w) / 2 );
    $y ||= 2 * int( ($yd-$h) / 2 );
  }
  $crop = "$w:$h:$x:$y";
  $dvd{title}{$title}{crop} = $crop;

  # Start, End
  my($start,$end) = split '-', $dvd{title}{$title}{sample};
  $end -= $start;
  my $cmd = sprintf qq,mplayer -vf rectangle=%s -dvd-device "%s" dvd://%d -ss %d -endpos %d, ,
    $crop, $dvd{src}, $title, $start, $end;
  warn "Running: $cmd\n";
  qx,$cmd,;
}

# List of an element is in an array
# #
sub inarray {
  my($elem,@list) = @_;

  for my $i ( @list ) {
    return 1 if $i eq $elem;
  }
  return undef;
}

# Compare two languages
#  - DA, first langauage is da
#  - da, any language is da
#  - none, empty choices
#  - orig, the first language
sub langcompare {
  my($pref,@lang) = @_;

  # There are no languages, and that's what we want
  return not undef if $pref eq 'none' and @lang == 0;

  # We do want languages, but there are none
  return undef if @lang == 0;

  # Choose first language
  return $lang[0] if $pref eq 'orig';

  if ( $pref eq uc $lang[0] ) {
    # Preferred language must be first
    return $lang[0];
  } else {
    # Preferred language must be among the choices
    return $pref if inarray($pref,@lang);
  }

  # None of our choices are available. And we are ok with no language then.
  return not undef if $pref eq 'none';

  # Nothing matches
  return undef;
}

# Select language according to preferences
# Uppercase for primary languages, lowercase for secondary
#
sub langselect {
  my $title = shift;
  #my @pref = qw(
  #  DA:jp DA:en JP:en JP:da EN:jp EN:da ORIG:en ORIG:jp ORIG:da
  #  da:jp da:en jp:en jp:da en:jp en:da orig:en orig:jp orig:da
  #  orig:orig
  #);
  my @pref = qw(
    DA:jp DA:en DA:none JA:en JA:da EN:ja EN:none JA:none
    da:jp da:en da:none ja:en ja:da en:ja en:none ja:none
  );
  my @audio = @{$dvd{title}{$title}{audiolang}};
  my @subtitle = @{$dvd{title}{$title}{subtitle}};
  my $primaudio = uc $audio[0];
  my $primsubt = uc $subtitle[0];
  # Run through preferences in order, and see if any can be honered
  my $choice;
  for my $p ( @pref ) {
    #warn "Test if $p match @audio:@subtitle\n";
    my($prefa,$prefs) = split /:/, $p;
    ## Primary Audio
    #if ( $prefa eq uc $prefa ) {
    #  if ( $prefa eq $primaudio or $prefa eq 'ORIG' ) {
    #    if ( $prefs eq uc $prefs ) {
    #      $choice = lc $p if $prefs eq $primsubt or $prefs eq 'ORIG';
    #    } elsif ( inarray($prefs,@subtitle) or $prefs eq 'orig' ) {
    #      $choice = lc $p;
    #    }
    #  }
    ## Secondary Audio
    #} elsif ( inarray($prefa,@audio) or $prefa eq 'orig' ) {
    #  if ( $prefs eq uc $prefs ) {
    #    $choice = lc $p if $prefs eq $primsubt or $prefs eq 'ORIG';
    #  } elsif ( inarray($prefs,@subtitle) or $prefs eq 'orig' ) {
    #    $choice = lc $p;
    #  }
    #}
    my $chosenlang = langcompare($prefa,@audio);
    next unless $chosenlang;
    my $chosensubt = langcompare($prefs,@subtitle);
    next unless $chosensubt;
    #last if $choice;
    $choice = lc $p;
    last;
  }
  if ( $choice ) {
    warn "Language Select: $choice (@audio:@subtitle)\n";
    #my($prefa,$prefs) = split /:/, $choice;
    #$dvd{title}{$title}{selectedaudio} = $prefa if $prefa;
    #$dvd{title}{$title}{selectedsubtitle} = $prefs if $prefs;
    langset($title, $choice);
    #x $title, $dvd{$title};
  } else {
    delete $dvd{title}{$title}{selected};
  }
}

# Set selected languages for a title
#
sub langset {
  my($title,$lang) = @_;

  my($audio,$subtitle) = split /:/, $lang;
  delete $dvd{title}{$title}{selectedaudio};
  delete $dvd{title}{$title}{selectedsubtitle};
  $dvd{title}{$title}{selectedaudio} = $audio
    if $audio and $audio ne 'none';
  $dvd{title}{$title}{selectedsubtitle} = $subtitle
    if $subtitle and $subtitle ne 'none';
}


########################################################################
### Pretty Printing
########################################################################

# Convert seconds to minutes
# XXX: And hours ?
#
sub humanduration {
  my $sec = shift;
  #if ( $sec >= 3600 ) {
    sprintf "%01d:%02d:%02d", int($sec/3600), int(($sec/60)%60), int($sec%60);
  #} else {
  #  sprintf "%d:%02d", int($sec/60), int($sec%60);
  #}
}

# Short string displaying title properties
#
sub titlesummary {
  my $title = shift;

  return sprintf "%7s,%2d,%s,%s,%s,%s",
    humanduration($dvd{title}{$title}{length}),
    $dvd{title}{$title}{chapters},
    $dvd{title}{$title}{videoresolution},
    $dvd{title}{$title}{displayresolution},
    join('-', @{$dvd{title}{$_}{audiolang}}),
    join('-', @{$dvd{title}{$_}{subtitle}}),
}

# Show encoding options
#
sub encodesummary {
  my $title = shift;

  my $encode = $dvd{title}{$title}{selected} ? 'Yes' : 'No';
  my $filled = sprintf "%.1f%%", 100*$dvd{title}{$title}{padding};
  my $audio = $dvd{title}{$title}{audiolang}
            ? join('-', @{$dvd{title}{$title}{audiolang}})
            : 'undef';
  my $subtitle = $dvd{title}{$title}{subtitle}
               ? join('-', @{$dvd{title}{$title}{subtitle}})
               : 'undef' ;
  
print <<EOF;

# Files
Track: $title
Input: $dvd{src}
File: $dvd{title}{$title}{file}
Folder: $dvd{folder}
Encode: $encode
Chapters: $dvd{title}{$title}{chapters}
Encode each chapter: $dvd{title}{$title}{eachchapter}
Sample: $dvd{title}{$title}{sample}
# Video
Video: $dvd{title}{$title}{videoresolution}
Display: $dvd{title}{$title}{displayresolution}
Anamorphic: $dvd{title}{$title}{anamorphic}
Crop: $dvd{title}{$title}{crop}
Resize: $dvd{title}{$title}{resize}
Screen Filled: $filled
# Audio
Audio Available: $audio
Audio Selected: $dvd{title}{$title}{selectedaudio}
# Subtitle
Subtitle Available: $subtitle
Subtitle Selected: $dvd{title}{$title}{selectedsubtitle}

EOF
}

########################################################################
### Menus
########################################################################

# Show Titles and let user select
#
sub selecttitles {
  my($default,@result);
  do {
    $default = join(',',
      grep $dvd{title}{$_}{selected}, sort { $a <=> $b } keys %{$dvd{title}}
    );
    @result = prompt(
      'm',
      {
         prompt => 'Select Titles',
         title  => 'Track,Length,#Chapters,Video,Display,Audio,Subtitle',
         items  => [
                      map {
                        ( $dvd{title}{$_}{selected} ? '(*) ' : '    ' ) .
                        titlesummary($_)
                      } sort { $a <=> $b } keys %{$dvd{title}}
                   ],
         return_base                => 1,
         accept_multiple_selections => 1,
         accept_empty_selection     => 1,
      },
      '1 2 3 ...',
      $default,
    );
    # Mark selected according to result
    delete $dvd{title}{$_}{selected}     for keys %{$dvd{title}};
           $dvd{title}{$_}{selected} = 1 for @result;
  } until $default eq join ',', @result;

  # Choose first track as current track
  ($dvd{current}) = 
    grep $dvd{title}{$_}{selected},
    keys %{$dvd{title}};
}

# Show Options Menu
#
sub menuoptions {
  my $result;
  do {
    print <<EOF;
Fine Tuning Options
-------------------
a) Autocrop            g) Folder                r) Resolution/Padding
b) Adjust crop         h) Chapter-by-Chapter    s) Preview start-end
c) Preview crop        i) Encoding Information  t) Track
d) Destination Device  l) Language              w) Write batch
f) File names          m) Menu                  q) Quit
                       p) Preview               u) Select/unselect
Current Track: $dvd{current}
EOF

    $result = prompt( 'x', 'Select Option', 'a ...', 'm' );
  } until $result !~ /^m/ and length $result > 0;
  return $result;
}

# Process input data from menu
#
sub tuning {
  my $done;
  do {
    my $response = menuoptions();
    for ( $response ) {
      /^a\s*(.*)/  and cropdetect($1 || $dvd{current}),         next;
      /^b\s*(.+)/  and cropset($dvd{current}, $1),              next;
      /^c\s*(.*)/  and croppreview($1 || $dvd{current}),        next;
      /^d/         and print "Not implemented\n";
      /^f\s+(.*)/  and $dvd{title}{$dvd{current}}{file} = $1,   next;
      /^g\s+(.*)/  and $dvd{folder} = $1,                       next;
      /^h\s*(.*)/  and chaptertogle($1 || $dvd{current}),       next;
      /^i\s*(\d*)/ and encodesummary($1 || $dvd{current}),      next;
      /^l\s+(.*)/  and langset($dvd{current}, $1),              next;
      /^m/         and                                          next;
      /^p/         and print "Not implemented\n";
      /^q/         and $done = 1,                               next;
      /^r/         and print "Not implemented\n";
      /^s+(.*)/    and $dvd{title}{$dvd{current}}{sample} = $1, next;
      /^t\s+(\d+)/ and $dvd{current} = $1,                      next;
      /^(\d+)/     and $dvd{current} = $1,                      next;
      /^u/         and print "Not implemented\n";
      /^w/         and writebatch(),                            next;
    }
  } until $done;
}

########################################################################
### Old Stuff
########################################################################

sub old_numtitles {
  my $input = shift;

  my $info = qx,$scandvd "$input" dvd:// 2>/dev/null,;
  #warn "info: $info";

  my($numtitles) = $info =~ /ID_DVD_TITLES=(\d+)/;
  return $numtitles;
}

 
# 720x480 854x480 704:464:10:6
# -> 
sub old_resize {
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

sub old_printout {
  print join "\t", @_;
}

# Read information about a Title
#  - Audio Language
#  - Subtitle languages
#  - Resolutions
#  - FPS
# 
sub old_dvdtitleinfo {
  my $title = shift;

  #warn "Getting lang, res for title $title\n";
  my $info = qx,$scandvd "$dvd{src}" dvd://$title 2>/dev/null,;
  my @lang = $info =~ /ID_AID_\d+_LANG=(\w+)/g;
  my @subt = $info =~ /ID_SID_\d+_LANG=(\w+)/g;
  my($chapters) = $info =~ /CHAPTERS: (\S+),/;
  $chapters ||= '';
  my @c = split ',', $chapters;
  $chapters = scalar @c;
  my($length) = $info =~ /ID_LENGTH=(\S+)/;
  my($resin,$resout) = $info =~ /VO: \[null\] (\d+x\d+) => (\d+x\d+)/;
  #my $crop = cropdetect($input,$title);
  #my @resize = resize($resin, $resout, $crop);
  #warn "resize: @resize\n";
  #return 
  #  $title,
  #  $length,
  #  $chapters,
  #  $resin,
  #  $resout,
  #  $crop,
  #  sprintf("%dx%d",@resize),
  #  sprintf("%.1f%%", 100 * $resize[2]),
  #  join(',',@lang),
  #  join(',',@subt),
  #  ;
  my %U;
  $dvd{title}{$title}{audiolang} = [ grep { !$U{$_}++ } @lang ];
  %U = ();
  $dvd{title}{$title}{subtitle}  = [ grep { !$U{$_}++ } @subt ];
  $dvd{title}{$title}{videoresolution} = $resin;
  $dvd{title}{$title}{displayresolution} = $resout;
  #x "title $title", $dvd{title}{$title};
}

#sub old_main {
#  my $titles = numtitles $ARGV[0];
#  printout "#title", "length", "#chap", qw(resin resout crop resize cover audio subtitle);
#  for my $t ( 1 .. $titles ) {
#    my @info = titleinfo($ARGV[0], $t);
#    next if $info[1] < 60;
#    my $min = sprintf "%d:%02d", int($info[1]/60), int($info[1]%60);
#    $info[1] = $min;
#    printout @info;
#  }
#}

########################################################################
### MAIN
########################################################################

sub usage {
  die <<EOF;
$0: <filename>
EOF
}

usage unless $ARGV[0];
die "cannot read $ARGV[0]\n" unless -r $ARGV[0];

dvdtitlescan($ARGV[0]);
for my $n ( keys %{$dvd{title}} ) {
  dvdtitleinfo($n);
}
#x '%dvd', \%dvd;
selecttitles();
tuning();

