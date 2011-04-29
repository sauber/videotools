#!/usr/bin/env perl

# Convert DVD or single video file input source to 720x480 mpeg4
# playable on PSP TV out.
# Soren - Apr 2011



########################################################################
### MEDIA
########################################################################

package Media;
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


########################################################################
### VIDEO CONTAINER
########################################################################

# General Video Stream Methods

package Video;
use Moose::Role;
use MooseX::Method::Signatures;

requires 'cmd_scanmedia';
requires 'cmd_titleinfo';
requires 'cmd_cropdetect';
requires 'titles';

# Uniq items in an array
#
sub uniq { my %U; grep { !$U{$_}++ } @_ }

# Extra attributes from one title
#
method titleinfo ( Str $title ) {
  my %info;

  # Scan the title for information
  my $cmd = $self->cmd_titleinfo( title=>$title );
  open SCAN, qq,$cmd 2>/dev/null |,;
    while (<SCAN>) {
      /ID_AID_\d+_LANG=(\w+)/ and push @{$info{audio}}   , $1;
      /ID_SID_\d+_LANG=(\w+)/ and push @{$info{subt}}    , $1;
      /CHAPTERS: (\S+),/      and        $info{chapters} = $1;
      /ID_LENGTH=([\d\.]+)/   and        $info{length}   = $1;
      /VO: \[null\] (\d+x\d+) => (\d+x\d+)/ and do {
         $info{videoresolution}   = $1;
         $info{displayresolution} = $2;
      };
    }
  close SCAN;
  $info{audio} = [ uniq( @{$info{audio}} ) ] if $info{audio};
  $info{subt}  = [ uniq( @{$info{subt}}  ) ] if $info{subt};

  return \%info;
}

# The title with given id
#
method idtitle ( Num $id ) {
  for my $t ( @{$self->titles} ) {
    #warn sprintf "*** idtitle %s vs. %s\n", $id, $t->id;
    return $t if $t->id eq $id;
  }
  return $self->titles->[0];
}



########################################################################
### FILE
########################################################################

# Methods that are specific to handle a Single Video File

package File;
use Moose;
use MooseX::Method::Signatures;
has 'media' => ( isa=>'Media', is =>'ro' );

method cmd_scanmedia {
  my $input = $self->media->source;
  return qq,mplayer -identify -frames 1 -vo null -ao null "$input",;
}

method cmd_titleinfo ( Str :$title? ) {
  my $input = $self->media->source;
  return qq,mplayer -identify -frames 1 -vo null -ao null "$input",;
}

method cmd_cropdetect {}

# A File only has one title
has titles => ( isa=>'ArrayRef[Title]', is=>'ro', lazy_build=>1 );
method _build_titles {[ Title->new( id=>0, container=>$self ) ]}

with 'Video';

__PACKAGE__->meta->make_immutable;


########################################################################
### DVD
########################################################################

# Methods that are specific to handling a DVD source with 1 or more titles

package DVD;
use Moose;
use MooseX::Method::Signatures;
has 'media' => ( isa=>'Media', is =>'ro', required=>1 );

our $scanmedia = 'mplayer -identify -frames 1 -vo null -ao null -dvd-device';

method cmd_scanmedia {
  my $input = $self->media->source;
  return qq,mplayer -identify -frames 1 -vo null -ao null -dvd-device "$input" dvd://,;
}

method cmd_titleinfo ( Str :$title ) {
  my $input = $self->media->source;
  return qq,mplayer -identify -frames 1 -vo null -ao null -dvd-device "$input" dvd://$title,;
}

method cmd_cropdetect {}

# All the titles on a DVD
#
has titles => ( isa=>'ArrayRef[Title]', is=>'ro', lazy_build=>1 );
method _build_titles {
  my $input = $self->media->source;
  my %title;
  open SCAN, qq,$scanmedia "$input" dvd:// 2>/dev/null |,;
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


########################################################################
### TITLE
########################################################################

package Title;
use Moose;
use MooseX::Method::Signatures;

has 'id'        => ( isa=>'Int', is =>'ro', required=>1 );
has 'container' => ( isa=>'Video', is =>'ro', required=>1 );
has 'media'     => ( isa=>'Media', is =>'ro' );
has 'chapters'  => ( isa=>'Int', is =>'ro' );
has 'length'    => ( isa=>'Num', is =>'ro' );
has 'selected'  => ( isa=>'Bool', is =>'rw', default=>method{1 if $self->length and $self->length > 120} );
has 'sample' => ( isa=>'Str', is=>'rw', default=>'25-75' );
has _info => ( isa=>'HashRef', is=>'ro', lazy_build=>1 );
method _build__info { $self->container->titleinfo($self->id) }
method audiolang         { $self->_info->{audiolang}         }
method subtitle          { $self->_info->{subtitle}          }
method videoresolution   { $self->_info->{videoresolution}   }
method displayresolution { $self->_info->{displayresolution} }
has 'cropline' => ( isa=>'Str', is=>'ro', lazy_build=>1 );
method _build_cropline {
  # Start and end
  my($start,$end) = split '-', $self->sample;
  $end -= $start; # End is length from start

  #my $cmd = sprintf 'mplayer -nosound -vo null -benchmark -vf cropdetect -ss %d -endpos %d -dvd-device "%s" dvd://%d 2>/dev/null',
  #  $start, $end, $dvd{src}, $title;
  $self->container->cropdetect($self->id);
}



__PACKAGE__->meta->make_immutable;

########################################################################
### BATCH CONVERSIONS TO BE DONE
########################################################################

package Batch;
use Term::Prompt;
use Moose;
use MooseX::Method::Signatures;

sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

has 'media' => ( isa=>'Media', is =>'ro' );
has 'title' => ( isa=>'Str', is=>'rw', default=>0 );

method menu {
  my $result;
  my $titleid = $self->media->container->titles->[$self->title]->id;
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
    my $title = $container->idtitle($self->title);
    #x 'current title', $title;
    my $response = $self->menu;
    for ( $response ) {
      /\w\s*(\d+)/ and $title = $container->idtitle($1); # Command local title
      /^(\d+)/     and $self->title($1),                        next;
      #/^a\s*(.*)/  and cropdetect($1 || $dvd{current}),          next;
      /^a/         and $title->cropdetect(),                     next;
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
}

# Print input and output data
#
method datadump {
  my $titles = $self->media->container->titles;
  for my $i ( 0 .. $#$titles ) {
    my $title = $titles->[$i];
    printf "Title %s\n", $title->id;
    print "  Input:\n";
    printf "    %s: %s\n", $_, $title->{$_} for keys %$title;
    print "  Output:\n";

  }
}

__PACKAGE__->meta->make_immutable;

########################################################################
### MAIN
########################################################################

sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

die "Usage: $0 <mediasource>\n" unless @ARGV;
my $media = Media->new( source => shift @ARGV );
#x 'media', $media->container->titles->[0]->_info;
Batch->new( media=>$media )->tuning;
