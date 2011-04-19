#!/usr/bin/env perl



########################################################################
### MEDIA
########################################################################

package Media;
use Moose;
use MooseX::Method::Signatures;

# Which file or dir to read from
has 'source' => ( isa=>'Str', is=>'ro' );

# Type of input source, dvd or file
has container => ( isa=>'Ref', is=>'ro', lazy_build=>1 );
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
### FILE
########################################################################

package File;
use Moose;
use MooseX::Method::Signatures;
has 'media' => ( isa=>'Ref', is =>'ro' );

our $scanmedia = 'mplayer -identify -frames 1 -vo null -ao null';

# A File only has one title
has titles => ( isa=>'ArrayRef[Title]', is=>'ro', lazy_build=>1 );
method _build_titles { return [ Title->new( id=>1, container=>$self ) ] }

method titleinfo {
  my $input = $self->media->source;
  my %info;
  open SCAN, qq,$scanmedia "$input" 2>/dev/null |,;
    while (<SCAN>) {
      /ID_LENGTH=([\d\.]+)/ and do {
        $info{length}   = $1;
      };
      /VO: \[null\] (\d+x\d+) => (\d+x\d+)/ and do {
        $info{videoresolution}   = $1;
        $info{displayresolution} = $2;

      };
    }
  close SCAN;
  return \%info;
}

__PACKAGE__->meta->make_immutable;


########################################################################
### DVD
########################################################################

package DVD;
use Moose;
use MooseX::Method::Signatures;
has 'media' => ( isa=>'Ref', is =>'ro', required=>1 );

our $scanmedia = 'mplayer -identify -frames 1 -vo null -ao null -dvd-device';

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

# Extra attributes from one title
#
method titleinfo ( Int $id ) {
  my $input = $self->media->source;

  # Scan the video
  my $info = qx,$scanmedia "$input" dvd://$id 2>/dev/null,;

  # Extra data
  my @audio = $info =~ /ID_AID_\d+_LANG=(\w+)/g;
  my @subt = $info =~ /ID_SID_\d+_LANG=(\w+)/g;
  my($chapters) = $info =~ /CHAPTERS: (\S+),/;
  $chapters ||= '';
  my @c = split ',', $chapters;
  $chapters = scalar @c;
  my($resin,$resout) = $info =~ /VO: \[null\] (\d+x\d+) => (\d+x\d+)/;
  my %A; my %S;

  return {
    audiolang         => [ grep { !$A{$_}++ } @audio ],
    subtitle          => [ grep { !$S{$_}++ } @subt  ],
    videoresolution   => $resin,
    displayresolution => $resout,
  };
}

__PACKAGE__->meta->make_immutable;


########################################################################
### TITLE
########################################################################

package Title;
use Moose;
use MooseX::Method::Signatures;

has 'id'        => ( isa=>'Int', is =>'ro', required=>1 );
has 'container' => ( isa=>'Ref', is =>'ro', required=>1 );
has 'media'     => ( isa=>'Ref', is =>'ro' );
has 'chapters'  => ( isa=>'Int', is =>'ro' );
has 'length'    => ( isa=>'Num', is =>'ro' );
has 'selected'  => ( isa=>'Bool', is =>'rw', default=>method{1 if $self->length and $self->length > 120} );
has _info => ( isa=>'HashRef', is=>'ro', lazy_build=>1 );
method _build__info { $self->container->titleinfo($self->id) }
method audiolang         { $self->_info->{audiolang}         }
method subtitle          { $self->_info->{subtitle}          }
method videoresolution   { $self->_info->{videoresolution}   }
method displayresolution { $self->_info->{displayresolution} }

__PACKAGE__->meta->make_immutable;


########################################################################
### MAIN
########################################################################

sub x {
 use Data::Dumper;
 warn Data::Dumper->Dump([$_[1]], ["*** $_[0]"]);
}

my $media = Media->new( source => shift @ARGV );
x 'media', $media->container->titles->[0]->_info;
