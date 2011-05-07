#!/usr/bin/env perl

# Convert DVD or single video file input source to 720x480 mpeg4
# playable on PSP TV out.
# Soren - May 2011


package Area;
########################################################################
### AREA
########################################################################

use Moose;
use MooseX::Method::Signatures;

# Width, height dimensions
has w => ( isa=>'Num', is=>'rw', default=>0 );
has h => ( isa=>'Num', is=>'rw', default=>0 );
has pixelaspect => ( isa=>'Num', is=>'rw', default=>1 );

# x,y offset
has x => ( isa=>'Num', is=>'ro', default=>0 );
has y => ( isa=>'Num', is=>'ro', default=>0 );

# Dimension aspect compensated for pixelaspect
#
method aspect {
  return 1 unless $self->h() > 0 and $self->w() > 0;
  return $self->w() / $self->h() * $self->pixelaspect;
}

# Render string
#
method wxh { sprintf "%dx%d", 0.5+$self->w, 0.5+$self->h }
method wch { sprintf "%d:%d", 0.5+$self->w, 0.5+$self->h }
method line { sprintf "%d:%d:%d:%d", 0.5+$self->w, 0.5+$self->h, 0.5+$self->x, 0.5+$self->y }

# Make a new Area object which is scaled to fit within target area
# Keep pixelaspect of target area.
#
method scale_to_fit ( Area $target ) {
  my $scaled = Area->new(
    w => $target->w,
    h => $target->h,
    pixelaspect => $target->pixelaspect,
  );
  my $stretch = $self->aspect / $target->aspect;
  #warn "*** Area scale_to_fit stretch $stretch\n";
  if ( $stretch > 1 ) {
    # Too wide, so reduce height
    $scaled->h( $scaled->h / $stretch );
  } else {
    # Too tall, so reduce width
    $scaled->w( $scaled->w * $stretch );
  }
  return $scaled;
}

# Calculate aspect as a fraction
#
method fraction {
  return '' unless $self->h and $self->w;
  my $gcf;
  my $y = int 0.5 + $self->h;
  my $x = int 0.5 + $self->w * $self->pixelaspect;
  # Find greatest common factor
  for my $n ( 1 .. $y ) {
    $gcf = $n if $y % $n == 0 and $x % $n == 0;
  }
  return sprintf "%d/%d", $x/$gcf, $y/$gcf;
}

# New object compensated for pixelaspect
#
method display {
  return Area->new( w=>$self->w * $self->pixelaspect, h=>$self->h );
}
  

__PACKAGE__->meta->make_immutable;


package Language;
########################################################################
### AREA
########################################################################

use Moose;
use MooseX::Method::Signatures;

# Chosen output languages
has audio    => ( isa=>'Str', is=>'rw', lazy_build=>1 );
method _build_audio    { (split /:/, $self->langpreferred)[0] || '' }
has subtitle => ( isa=>'Str', is=>'rw', lazy_build=>1 );
method _build_subtitle { (split /:/, $self->langpreferred)[1] || '' }

# Set of languages available in input
has available_audio    => ( isa=>'ArrayRef[Str]', is=>'rw' );
has available_subtitle => ( isa=>'ArrayRef[Str]', is=>'rw' );

# Select language according to preferences
# Uppercase for primary languages, lowercase for secondary
#
# DA or JA is main audio, use if suitable subtitles
#   DA audio, ja subt
#   JA audio, da subt
#   DA audio, en subt
#   JA audio, en subt
#
# DA or JA is available audio, try suitable subtitles
#   da audio, ja subt
#   ja audio, da subt
#   da audio, en subt
#   ja audio, en subt
#   da audio, none subt
#   ja audio, none subt
#
# EN is available audio, try JA subtitle
#   en audio, ja subt
#   en audio, none subt
#
# No preferred audio available, try subtitles
#   ORIG audio, en subt
#   ORIG audio, ja subt
#   ORIG audio, da subt
#   ORIG audio, ORIG subt
#   ORIG audio, none subt

# No audio is available, try subtitles
#   none audio, ORIG subt
#   none audio, none subt
#
has preference => ( isa=>'ArrayRef[Str]', is=>'ro', default=>sub
  { [ qw(
      DA:jp
      JA:da
      DA:en
      JA:en

      da:ja
      ja:da
      da:en
      ja:en
      da:none
      ja:none

      en:ja
      en:none

      orig:en
      orig:ja
      orig:da
      orig:orig
      orig:none

      none:orig
      none:none
    ) ] }
);

# Element is in an array
#
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
  return '' if $pref eq 'none' and @lang == 0;

  # We do want languages, but there are none
  return undef if @lang == 0;

  # Choose first language
  return $lang[0] if $pref eq 'orig';

  # Preferred language is first
  return $lang[0] if $pref eq uc $lang[0];

  # Preferred language is among the choices
  return $pref if inarray($pref,@lang);

  # No language is ok
  return '' if $pref eq 'none';

  # Nothing matches
  return undef;
}



has langpreferred => ( isa=>'Str', is=>'ro', lazy_build=>1 );
method _build_langpreferred {
  # Available languages in input
  my @audio    = @{ $self->available_audio    };
  my @subtitle = @{ $self->available_subtitle };
  my @pref     = @{ $self->preference };

  my $primaudio = uc $audio[0]    if $audio[0];
  my $primsubt  = uc $subtitle[0] if $subtitle[0];

  # Run through preferences in order, and see if any can be honered
  my $language = '';
  for my $p ( @pref ) {
    #warn "*** langpreferred test if $p match @audio:@subtitle\n";
    my($prefa,$prefs) = split /:/, $p;
    my $chosenlang = langcompare($prefa,@audio);
    next unless defined $chosenlang;
    my $chosensubt = langcompare($prefs,@subtitle);
    next unless defined $chosensubt;
    #last if $choice;
    #$language = lc $p;
    $language = "$chosenlang:$chosensubt";
    #warn "*** langpreferred is $language\n";
    last;
  }

  #warn sprintf "*** Language Auto Select: %s from (@audio:@subtitle)\n",
  #  ( $language || '(undef)' );
  return $language;
}

# User defined output languages
method set ( Str $lang ) {
  #warn "*** Title langset $lang\n";
  #my @audio    = @{ $self->audiolang };
  #my @subtitle = @{ $self->subtitle  };
  #warn "*** Language Auto Select: $lang from (@audio:@subtitle)\n";

  my($audio,$subtitle) = split /[\s:\,]/, $lang;
  $self->audio(    $audio    );
  $self->subtitle( $subtitle );
}

# Show langauges as string
#   en-*da-it:*en-da-it
method summary {
  join ':',
    join('-',
      map { $_ eq $self->audio ? "*$_" : $_ }
      @{ $self->available_audio }
    ),
    join('-',
      map { $_ eq $self->subtitle ? "*$_" : $_ }
      @{ $self->available_subtitle }
    ),
  ;
}


__PACKAGE__->meta->make_immutable;


package Media;
########################################################################
### MEDIA
########################################################################

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Method::Signatures;

subtype 'FileName'
  => as 'Str'
  => where { -e $_ }
  => message { "File Error: $_ not found\n" };

# Which file or dir to read from
has 'source' => ( isa=>'FileName', is=>'ro' );

# Type of input source, dvd or file
has container => ( isa=>'Video', is=>'ro', lazy_build=>1 );
method _build_container {
  # A dir, a .iso and .dmg are considered to be DVD container
  return DVD->new( media => $self )
    if -d $self->source
       or $self->source =~ /\.iso$/
       or $self->source =~ /\.img$/;
  return File->new( media => $self );
}

has batchname => ( isa=>'Str', is=>'ro', default=>sub{
  my $source = shift->source;
  $source =~ s,/*+$,,; # Remove trailing /
  $source . ".batch.sh";
});

has dstfolder => ( isa=>'Str', is=>'ro', default=>sub{
  my $source = shift->source;
  $source =~ s,/*+$,,; # Remove trailing /
  $source . ".psp";
});

method write_batch {
  warn sprintf "*** media write_batch write to %s\n", $self->batchname;
  open BATCH, ">" . $self->batchname;
    printf BATCH 'mkdir "%s"', $self->dstfolder;
    print BATCH "\n\n";
    for my $title ( $self->container->selectedtitles ) {
      if ( $title->chapterbychapter ) {
        for my $chapter ( 1 .. $title->chapters ) {
          print BATCH $self->container->cmd( 'encode', $title, $chapter );
        }
      } else {
        print BATCH $self->container->cmd( 'encode', $title );
      }
    }
  close BATCH;
}


sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

__PACKAGE__->meta->make_immutable;


package Video;
########################################################################
### VIDEO CONTAINER
########################################################################
# General Video Stream Methods

use Moose::Role;
use MooseX::Method::Signatures;
use Carp qw(confess);
use feature "switch";

requires 'titles';
requires 'titlesource';

# Various command to extract data, preview and render
#
method cmd ( Str $action, Ref $title?, Int $chapter? ) {
  given ( $action ) {
    when ( 'scanmedia' ) { return sprintf
      'mplayer -identify -frames 0 -vo null -ao null %s',
      $self->mediasource()
    }

    when ( 'titleinfo' ) { return sprintf
      'mplayer -identify -frames 1 -vo null -ao null %s',
      $self->titlesource( $title )
    }

    when ( 'cropdetect' ) { return sprintf
      'mplayer -nosound -vo null -benchmark -vf cropdetect -ss %d -endpos %d %s',
      $title->samplestart,
      $title->samplelength,
      $self->titlesource( $title )
    }

    when ( 'preview' ) {
      my @opt;
      push @opt, sprintf("-ss %s", $title->samplestart)
        if $title->samplestart > 0;
      push @opt, sprintf("-endpos %s", $title->samplelength)
        if $title->samplelength < int $title->length;
      push @opt, sprintf("-vf rectangle=%s", $title->crop->line)
        if $title->crop->wch ne $title->video->wch;
      push @opt, sprintf("-aid %d", $title->language->audio)
        if $title->language->audio =~ /^\d+$/;
      push @opt, sprintf("-alang %s", $title->language->audio)
        if $title->language->audio =~ /^\D+$/;
      push @opt, sprintf("-sid %d", $title->language->subtitle)
        if $title->language->subtitle =~ /^\d+$/;
      push @opt, sprintf("-slang %s", $title->language->subtitle)
        if $title->language->subtitle =~ /^\D+$/;

      return sprintf
        'mplayer %s %s', join(' ', @opt), $self->titlesource( $title );
    }

    when ( 'encode' ) {
      # Input Video Filter
      my $vf = "-vf kerndeint";
      $vf .= sprintf ",crop=%s", $title->crop->line
        if $title->crop->line ne $title->video->line;
      $vf .= sprintf ",scale=%s", $title->crop->scale_to_fit($title->device)->wch
        if $title->crop->scale_to_fit($title->device)->wxh ne $title->video->wxh;
      $vf .= sprintf ",expand=%s", $title->device->wch;
      $vf .= ",dsize=16/9,pp=al,denoise3d";
     
      # Language/Chapter Filter
      my @opt;
      push @opt, sprintf("-aid %d", $title->language->audio)
        if $title->language->audio =~ /^\d+$/;
      push @opt, sprintf("-alang %s", $title->language->audio)
        if $title->language->audio =~ /^\D+$/;
      push @opt, sprintf("-sid %d", $title->language->subtitle)
        if $title->language->subtitle =~ /^\d+$/;
      push @opt, sprintf("-slang %s", $title->language->subtitle)
        if $title->language->subtitle =~ /^\D+$/;
      push @opt, sprintf("-chapter %d-%d", $chapter, $chapter)
        if $chapter;

      my $target = '"' . $self->media->dstfolder . '"/'
                 . $self->titletarget( $title, $chapter );

      return sprintf 'mencoder %s \
  %s %s \
  -oac pcm -af volnorm \
  -ovc lavc -lavcopts vcodec=ffvhuff \
  -o %s.tmp

ffmpeg -i %s.tmp \
  -ac 2 \
  -vcodec libx264 \
  -vpre normal \
  -vpre main \
  -level 30 \
  -b 1400k \
  -s %s \
  -aspect 16:9 \
  -y %s

rm %s.tmp

',
        $self->titlesource( $title ),
        $vf,
        join('', map "\\\n  $_", @opt ),
        $target,
        $target,
        $title->device->wxh,
        $target,
        $target,
    }
  }
  die "No $action action not defined";
}


# Uniq items in an array
#
sub uniq { my %U; grep { !$U{$_}++ } @_ }

# Debug
sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

# Extra attributes from one title
#
method titleinfo ( Ref $title ) {
  my $cmd = $self->cmd( 'titleinfo', $title );
  warn "*** titleinfo $cmd\n";


  # Scan the title for information
  my %info;
  open SCAN, qq,$cmd 2>/dev/null |,;
  #x 'container titleinfo', $self->titles;
    while (<SCAN>) {
      /ID_AID_\d+_LANG=(\w+)/  and push @{ $info{audiolang} } , $1;
      /ID_SID_\d+_LANG=(\w+)/  and push @{ $info{subtitle}  } , $1;
      /CHAPTERS: (\S+),/       and         $info{chapters}    = $1;
      /ID_LENGTH=([\d\.]+)/    and         $info{length}      = $1;
      /ID_VIDEO_FPS=([\d\.]+)/ and         $info{fps}         = $1;
      /VO: \[null\] (\d+x\d+) => (\d+x\d+)/ and do {
         $info{video}   = $1;
         $info{display} = $2;
         #$info{video}   = Area->new( w=>$1, h=>$2, pixelaspect=>($3/$4)/($1/$2) );
         #$info{displayresolution} = Area->new( w=>$3, h=>$4 );
      };
    }
  #x 'container titleinfo', $self->titles;
  close SCAN;
  $info{audiolang} = [ uniq( @{$info{audiolang}} ) ] if $info{audiolang};
  $info{subtitle}  = [ uniq( @{$info{subtitle}}  ) ] if $info{subtitle} ;

  #x "$title->id titleinfo", \%info;
  return \%info;
}

# The title with given id
#
method idtitle ( Num $id ) {
  for my $t ( @{$self->titles} ) {
    unless ( defined $t ) {
      x "idtitle has no id to match $id", $self->titles unless defined $t;
      confess;
    }
    #warn sprintf "*** idtitle %s vs. %s\n", $id, $t->id;
    return $t if $t->id eq $id;
  }
  return $self->titles->[0];
}

# Titles that are selected
#
method selectedtitles {
  grep $_->selected, @{$self->titles}
}


package File;
########################################################################
### FILE
########################################################################

# Methods that are specific to handle a Single Video File

use Moose;
use MooseX::Method::Signatures;
has 'media' => ( isa=>'Media', is =>'ro' );

method mediasource  {
  '"' . $self->media->source . '"';
}

method titlesource ( Ref $title? )  {
  $self->mediasource;
}

method titletarget ( Ref $title?, Any $chapter? ) {
  my $file = $self->media->source;
  $file =~ s/(\.\w+)$/.psp.mp4/;
  return '"' . $file . '"';
}

# A File only has one title
has titles => ( isa=>'ArrayRef[Title]', is=>'ro', lazy_build=>1 );
method _build_titles {[ Title->new( id=>1, container=>$self ) ]}

with 'Video';

__PACKAGE__->meta->make_immutable;


package DVD;
########################################################################
### DVD
########################################################################

# Methods that are specific to handling a DVD source with 1 or more titles

use Moose;
use MooseX::Method::Signatures;
has 'media' => ( isa=>'Media', is =>'ro', required=>1 );

method mediasource  {
  my $input = $self->media->source;
  return qq,-dvd-device "$input" dvd://,;
}

method titlesource ( Ref $title )  {
  $self->mediasource . $title->id;
}

method titletarget ( Ref $title?, Any $chapter? ) {
  my $file = $self->media->source;
  $file =~ s/\/$//; # Remove trailing /
  $file =~ s/.*\///; # Remove dirs
  $file .= sprintf "-%02d", $title->id;
  $file .= sprintf "-%02d", $chapter if $chapter;
  '"' . $file . '.psp.mp4"';
}

# All the titles on a DVD
#
has titles => ( isa=>'ArrayRef[Title]', is=>'ro', lazy_build=>1 );
method _build_titles {
  #my $input = $self->media->source;
  my $cmd = $self->cmd( 'scanmedia' );
  warn "*** scanmedia $cmd\n";
  my %title;
  #open SCAN, qq,$scanmedia "$input" dvd:// 2>/dev/null |,;
  open SCAN, qq,$cmd 2>/dev/null |,;
    while (<SCAN>) {
      /ID_DVD_TITLE_(\d+)_CHAPTERS=(\d+)/   and $title{$1}{chapters} = $2;
      /ID_DVD_TITLE_(\d+)_LENGTH=([\d\.]+)/ and $title{$1}{length}   = $2;
    }
  close SCAN;

  return [ map Title->new(
      id        => $_,
      container => $self,
      ( $title{$_}{length}   ? ( length   => $title{$_}{length}   ) : () ),
      ( $title{$_}{chapters} ? ( chapters => $title{$_}{chapters} ) : () ),
    ), sort { $a <=> $b } grep /^\d+$/, keys %title ];

}

with 'Video';

__PACKAGE__->meta->make_immutable;


package Title;
########################################################################
### TITLE
########################################################################

use Moose;
use Carp qw(confess);
use MooseX::Method::Signatures;

sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

has 'id'        => ( isa=>'Int', is =>'ro', required=>1 );
has 'container' => ( isa=>'Video', is =>'ro', required=>1 );
has 'media'     => ( isa=>'Media', is =>'ro' );
has 'chapters'  => ( isa=>'Int', is =>'ro', default=>1 );
has 'chapterbychapter'  => ( isa=>'Bool', is =>'rw', default=>0 );
has 'sample' => ( isa=>'Str', is=>'rw', default=>'25-75' );

has 'selected'  => ( isa=>'Bool', is =>'rw', default=>method{1 if $self->length and $self->length > 120} );

has _input => ( isa=>'HashRef', is=>'ro', lazy_build=>1 );
method _build__input { $self->container->titleinfo($self) }

method fps               { $self->_input->{fps}               }
has video => ( isa=>'Area', is=>'ro', lazy_build=>1 );
method _build_video   {
  return new Area unless $self->_input->{video} and $self->_input->{display};
  my($w,$h) = split /[x:]/, $self->_input->{video};
  my($x,$y) = split /[x:]/, $self->_input->{display};
  return Area->new( w=>$w, h=>$h, pixelaspect=>($x/$y)/($w/$h) );
}

has language => ( isa=>'Language', is=>'ro', lazy_build=>1 );
method _build_language {
  return Language->new(
    available_audio    => ( $self->_input->{audiolang} || [] ),
    available_subtitle => ( $self->_input->{subtitle}  || [] ),
  );
}

has 'length'    => ( isa=>'Num', is =>'ro', lazy_build=>1 );
method _build_length { $self->_input->{length} || 0 }

has 'crop' => ( isa=>'Area', is=>'rw', lazy_build=>1 );
method _build_crop { $self->video }

method cropdetect {
  my $cmd = $self->container->cmd( 'cropdetect', $self );
  
  warn "*** cropdetect $cmd\n";

  # Look for
  #   [CROP] Crop area: X: 0..719  Y: 0..477  (-vf crop=720:464:0:8).
  my $crop;
  open CROP, qq,$cmd 2>/dev/null |,;
    while(<CROP>){
      #print;
      next unless /CROP/;
      chomp;
      $crop = $_;
    }
  close CROP;

  if ( $crop ) {
    # Cropping detected
    warn "*** crop $crop\n";
    $crop =~ /crop=([\d\:]+)/ and my @d = split /[:x]/, $1;
    return Area->new(
      w => $d[0], h => $d[1],
      x => $d[2], y => $d[3],
      pixelaspect=> $self->video->pixelaspect,
    );
  } else {
    # no cropping detected so use full resolution
    return $self->video;
  }
}

# Video resolution of target device
#
# Device resolution depends on frame rate
# According to AVC level 3.0 specs:
# rate < 25 => 720x576
# rate < 30 => 720x480
#
# XXX: TODO Internal screen is 3:2, but TV-out is 16:9
#
has device => (
  isa=>'Area',
  is=>'ro',
  default=>sub {
    my $self = shift;
    my $h = ( $self->fps and $self->fps <= 25 ) ? 576 : 480;
    return Area->new( w=>720, h=>$h, pixelaspect=>(16/9)/(720/$h) );
  },
);

method preview {
  my $cmd = $self->container->cmd( 'preview', $self );
  warn "*** title preview $cmd\n";
  qx,$cmd,;
}

# For crop detect and for render sample, decide length of sample
#
method samplelength {
  my($start,$end) = split /-/, $self->sample;
  if ( $end-$start > $self->length ) {
    # Desired sample longer than video, so choose whole video
    return $self->length;
  } else {
    # Video long enough to use full desired sample length
    return $end-$start;
  }
}

# For crop detect and for render sample, decide startpoint of sample
#
method samplestart {
  my($start,$end) = split /-/, $self->sample;
  if ( $end-$start > $self->length ) {
    # Desired sample longer than video, so start from beginning
    return 0;
  } elsif ( $end > $self->length ) {
    # Desired sample end is beyond end of video. Choose middle of video
    return ( $self->length - ( $end-$start ) ) / 2;
  } else {
    # Video long enough to use full desired sample length
    return $start;
  }
}

method humanduration {
  my $sec = $self->length;
  sprintf "%01d:%02d:%02d", int($sec/3600), int(($sec/60)%60), int($sec%60);
}

# A short description of title
#
method titlesummary {
  my $summary = sprintf "%7s,%2d,%s,%s,%s",
    $self->humanduration,
    $self->chapters,
    ( $self->video   ? $self->video->wxh   : '0x0'),
    ( $self->video ? $self->video->fraction : ''),
    $self->language->summary,
    #join('-', $self->audiolang ? @{$self->audiolang} : () ),
    #join('-', $self->subtitle  ? @{$self->subtitle}  : () ),
    qw(4 5 6);
  #x 'titlesummary', $self;
  return $summary;
}


sub DEMOLISH {
  confess;
}

__PACKAGE__->meta->make_immutable;


package Batch;
########################################################################
### BATCH CONVERSIONS TO BE DONE
########################################################################

use Term::Prompt;
use feature "switch";
use Moose;
use MooseX::Method::Signatures;

sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

has 'media'   => ( isa=>'Media', is =>'ro' );

# Current title. Defaults to longest title.
has 'title' => ( isa=>'Title', is=>'rw', lazy_build=>1 );
method _build_title {
  my $longest;
  for my $title ( $self->media->container->selectedtitles ) {
    $longest = $title, next unless $longest;
    $longest = $title if
      $title->length and $longest->length and
      $title->length  >  $longest->length;
  }
  return $longest;
}

# Print all titles, confirm selection of which titles to include in batch
#
method selecttitles {
  my $titles = $self->media->container->titles;
  my($default,@result);
  do {
    $default = join ',', map $_->id, grep $_->selected, @$titles;
    my @items;
    for my $t ( @$titles ) {
      push @items,
        ( $t->selected ? '(*) ' : '    ' ) .
        $t->titlesummary
    }
    #x "selecttitles", $titles;
    
    @result = prompt(
      'm',
      {
         prompt => 'Select Titles',
         title  => 'Track,Length,#Chapters,Video,Display,Audio:Subtitle',
         items  => \@items,
         return_base                => 1,
         accept_multiple_selections => 1,
         accept_empty_selection     => 1,
      },
      '1 2 3 ...',
      $default,
    );
    # Mark selected according to result
    #x "selecttitles", $titles;
    $_->selected(0) for @$titles;
    $_->selected(1) for map $self->media->container->idtitle($_), @result;
  } until $default eq join ',', @result;
  return $self;
}

# Print a menu of available tuning options
# #
method menu {
  my $result;
  my $titleid = $self->title->id;
  do {
    print <<EOF;
Video Conversion Options
------------------------
a) Autocrop [n]           h) Chapter-by-Chapter [n]  s) Preview start-end
b) Adjust crop [w:h:x:y]  i) Encoding Information    w) Write batch
c) Cancel crop [n]        l) Language [a:s]          q) Quit
                          p) Preview [n]
Current Title: $titleid
EOF

    $result = prompt( 'x', 'Select Option', 'a ...', 'm' );
  } until $result !~ /^m/ and length $result > 0;
  return $result;
}

# Print menu, read user input and process
#
method tuning {
  my $done;
  do {
    #$self->datadump;
    my $container = $self->media->container;
    my $title = $self->title;
    #x 'current title', $title;

    # Read command and arg
    my $response = $self->menu;
    my $command = ''; my $arg;
    $response =~ /^(\w)\s*(.*?)s*$/ and do { $command = $1; $arg = $2 };

    # Command runs on a specific title instead of current title
    $title = $container->idtitle($arg) if $arg and $arg =~ /^\d+$/;

    given ( $command ) {
      # Select Title, Info, Preview, Write, Quit
      when ( /^\d$/ ) { $self->title($container->idtitle($command)) }
      when ( 'i'    ) { $self->datadump }
      when ( 'p'    ) { $title->preview }
      when ( 'q'    ) { $done = 1 }
      when ( 'w'    ) { $self->media->write_batch }

      # Cropping
      when ( 'a' ) { $title->crop($title->cropdetect)                      }
      when ( 'b' ) { my%c; @c{qw(w h x y)}=split /[x:]/,$arg; $title->crop(Area->new(%c,pixelaspect=>$title->video->pixelaspect)) }
      when ( 'c' ) { $title->crop($title->video)                 }

      # Language, Chapters, Sample
      when ( 'l' ) { $title->language->set($arg) }
      when ( 'h' ) { $title->chapterbychapter(1-$title->chapterbychapter) }
      when ( 's' ) { $title->sample($arg) }
    }
  } until $done;
  return $self;
}

# Print input and output data for selected titles
#
method datadump {
  for my $title ( $self->media->container->selectedtitles ) {
    printf "Title %s\n", $title->id;
    print  "  Input:\n";
    printf "    %-8s: %s\n", ucfirst($_), $title->$_ for qw(length fps chapters);
    printf "    Video   : %s\n", $title->video->wxh;
    printf "    Display : %s\n", $title->video->display->wxh;
    printf "    Aspect  : %s\n", $title->video->fraction;
    printf "    Audio   : %s\n", join ',', @{ $title->language->available_audio };
    printf "    Subtitle: %s\n", join ',', @{ $title->language->available_subtitle };
    print  "  Output:\n";
    printf "    Audio   : %s\n", $title->language->audio;
    printf "    Subtitle: %s\n", $title->language->subtitle;
    printf "    Each chp: %s\n", $title->chapterbychapter;
    printf "    Device  : %s\n", $title->device->wxh;
    printf "    Crop    : %s\n", $title->crop->line;
    printf "    Resize  : %s\n", $title->crop->scale_to_fit($title->device)->wxh;
    printf "    Sample  : %s\n", join '-', $title->samplestart, $title->samplestart+$title->samplelength;
    printf "    Batch   : %s\n", $self->media->batchname;
    printf "    Target  : %s\n", $self->media->dstfolder;

  }
  return $self;
}

__PACKAGE__->meta->make_immutable;


########################################################################
### MAIN
########################################################################

#sub x {
# use Data::Dumper;
# warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
#}

die "Usage: $0 <mediasource>\n" unless @ARGV;
my $media = Media->new( source => shift @ARGV );
#x 'media', $media->container->titles->[0]->_input;
Batch->new( media=>$media )->selecttitles->datadump->tuning;

# Test resizing
#my $video = Area->new( w=>720, h=>576, pixelaspect=>(1024/720) );
#my $psp = Area->new( w=>720, h=>480, pixelaspect=>(16/9)/(720/480) );
#print $video->scale_to_fit( $psp )->wch;
