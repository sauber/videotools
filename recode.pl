#!/usr/bin/env perl

# Convert DVD or single video file input source to 720x480 mpeg4
# playable on PSP TV out.
# Soren - Apr 2011




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

sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

__PACKAGE__->meta->make_immutable;


# General Video Stream Methods

package Video;
########################################################################
### VIDEO CONTAINER
########################################################################

use Moose::Role;
use MooseX::Method::Signatures;
use Carp qw(confess);

requires 'titles';
requires 'titlesource';

# Various command to extract data, preview and render
#
method cmd ( Str $action, Ref $title? ) {
  for ( $action ) {

    /scanmedia/ and return sprintf
      'mplayer -identify -frames 1 -vo null -ao null %s',
      $self->mediasource();

    /titleinfo/ and return sprintf
      'mplayer -identify -frames 1 -vo null -ao null %s',
      $self->titlesource( $title );

    /cropdetect/ and return sprintf
      'mplayer -nosound -vo null -benchmark -vf cropdetect -ss %d -endpos %d %s',
      $title->samplestart,
      $title->samplelength,
      $self->titlesource( $title );

    /croppreview/ and return sprintf
      'mplayer -vf %s -ss %d -endpos %d %s',
      $title->cropline,
      $title->samplestart,
      $title->samplelength,
      $self->titlesource( $title );
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
      /ID_AID_\d+_LANG=(\w+)/ and push @{ $info{audiolang} } , $1;
      /ID_SID_\d+_LANG=(\w+)/ and push @{ $info{subtitle}  } , $1;
      /CHAPTERS: (\S+),/      and         $info{chapters}    = $1;
      /ID_LENGTH=([\d\.]+)/   and         $info{length}      = $1;
      /VO: \[null\] (\d+x\d+) => (\d+x\d+)/ and do {
         $info{videoresolution}   = $1;
         $info{displayresolution} = $2;
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

# A File only has one title
has titles => ( isa=>'ArrayRef[Title]', is=>'ro', lazy_build=>1 );
method _build_titles {[ Title->new( id=>0, container=>$self ) ]}

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

#our $scanmedia = 'mplayer -identify -frames 1 -vo null -ao null -dvd-device';

method mediasource  {
  my $input = $self->media->source;
  return qq,-dvd-device "$input" dvd://,;
}

method titlesource ( Ref $title )  {
  $self->mediasource . $title->id;
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
    ), sort keys %title ];

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
has 'chapters'  => ( isa=>'Int', is =>'ro' );
has 'sample' => ( isa=>'Str', is=>'rw', default=>'25-75' );

has 'selected'  => ( isa=>'Bool', is =>'rw', default=>method{1 if $self->length and $self->length > 120} );

has _info => ( isa=>'HashRef', is=>'ro', lazy_build=>1 );
#method _build__info { $self->container->titleinfo($self) }
method _build__info {
  #x '_info containter titles', $self->container->titles;
  my $info = $self->container->titleinfo($self);
  #x '_info', $info;
  #x '_info containter titles', $self->container->titles;
  return $info;
 }

method audiolang         { $self->_info->{audiolang}         }
method subtitle          { $self->_info->{subtitle}          }
method videoresolution   { $self->_info->{videoresolution}   }
method displayresolution { $self->_info->{displayresolution} }

has 'length'    => ( isa=>'Num', is =>'ro', lazy_build=>1 );
method _build_length { $self->_info->{length} }

has 'cropline' => ( isa=>'Str', is=>'rw', lazy_build=>1 );
method _build_cropline { $self->cropdetect }


method cropdetect {
  my $cmd = $self->container->cmd( 'cropdetect', $self );
  
  warn "*** cropdetect $cmd\n";

  # Look for
  #   [CROP] Crop area: X: 0..719  Y: 0..477  (-vf crop=720:464:0:8).
  my $cropline;
  open CROP, qq,$cmd 2>/dev/null |,;
    while(<CROP>){
      #print;
      next unless /CROP/;
      chomp;
      $cropline = $_;
    }
  close CROP;

  if ( $cropline ) {
    # Cropping detected
    warn "*** cropline $cropline\n";
    $cropline =~ /crop=([\d\:]+)/ and return $1;
  } else {
    # no cropping detected so use full resolution
    return $self->videoresolution;
  }
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
  my $summary = sprintf "%7s,%2d,%s,%s,%s,%s",
    $self->humanduration,
    $self->chapters,
    $self->videoresolution,
    $self->displayresolution,
    join('-', $self->audiolang ? @{$self->audiolang} : () ),
    join('-', $self->subtitle  ? @{$self->subtitle}  : () ),
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
  for my $obj ( @{ $self->media->container->titles } ) {
    $longest = $obj, next unless $longest;
    $longest = $obj if
      $obj->length and $longest->length and
      $obj->length  >  $longest->length;
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
    #x "selecttitles", $titles;
    #my @items = map {
    #  ( $_->selected ? '(*) ' : '    ' ) .
    #  #'str'
    #   $_->titlesummary
    #} @$titles;
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
         title  => 'Track,Length,#Chapters,Video,Display,Audio,Subtitle',
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
  #my $titleid = $self->media->container->titles->[$self->title]->id;
  my $titleid = $self->title->id;
  do {
    print <<EOF;
Video Conversion Options
------------------------
a) Autocrop [n]        g) Folder                r) Resolution/Padding
b) Adjust crop         h) Chapter-by-Chapter    s) Preview start-end
c) Preview crop [n]    i) Encoding Information  t) Change Title
d) Destination Device  l) Language              w) Write batch
f) File names          m) Menu                  q) Quit
                       p) Preview               u) Select/unselect
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
    $self->datadump;
    my $container = $self->media->container;
    my $title = $self->title;
    #x 'current title', $title;
    my $response = $self->menu;
    for ( $response ) {
      /\w\s*(\d+)/ and $title = $container->idtitle($1); # Command local title
      /^(\d+)/     and $self->titleid($1),                        next;
      #/^a\s*(.*)/  and cropdetect($1 || $dvd{current}),          next;
      /^a/         and $title->cropline(),                     next;
      #/^b\s*(.+)/  and cropset($dvd{current}, $1),               next;
      #/^c\s*(.*)/  and croppreview($1 || $dvd{current}),         next;
      #/^d/         and print "Not implemented\n";
      #/^f\s+(.*)/  and $dvd{title}{$dvd{current}}{file} = $1,    next;
      #/^g\s+(.*)/  and $dvd{folder} = $1,                        next;
      #/^h\s*(.*)/  and chaptertogle($1 || $dvd{current}),        next;
      #/^i\s*(\d*)/ and encodesummary($1 || $dvd{current}),       next;
      #/^l\s+(.*)/  and langset($dvd{current}, $1),               next;
      #/^m/         and                                           next;
      #/^p/         and $dvd{title}{preview} = $1,                next;
      /^q/         and $done = 1,                                next;
      #/^r/         and print "Not implemented\n";
      #/^s+(.*)/    and $dvd{title}{$dvd{current}}{sample} = $1,  next;
      #/^t\s+(\d+)/ and $dvd{current} = $1,                       next;
      #/^(\d+)/     and $dvd{current} = $1,                       next;
      #/^u/         and print "Not implemented\n";
      #/^w/         and writebatch(),                             next;
    }
  } until $done;
  return $self;
}

# Print input and output data
#
method datadump {
  my $titles = $self->media->container->titles;
  for my $i ( 0 .. $#$titles ) {
    my $title = $titles->[$i];
    printf "Title %s\n", $title->id;
    print "  Input:\n";
    printf "    %s: %s\n", $_, $title->{$_} for grep defined $title->{$_}, keys %$title;
    print "  Output:\n";

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
#x 'media', $media->container->titles->[0]->_info;
Batch->new( media=>$media )->selecttitles->tuning;
