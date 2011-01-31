## A simple class. Creates readonly accessors for
## whatever is passed to it's new method.
## Also includes 'namespace' and 'tags' methods compatible
## with Template::TAL::Language so this can be used as the
## base class for Template::TAL plugins as well.

package GreyNoise::Plugin;

use warnings;
use strict;
use Carp qw( croak );

## new, create a new object with a simple accessor model.
## example: 
##   my $plugin = GreyNoise::Plugin->new( hi => 'hello world' );
##   say $plugin->hi;
##
sub new {
  my $class = shift;
  my %data  = @_;
  my $self = bless \%data, $class;
  foreach my $attribute (keys %data) {
    $self->add_accessor($attribute);
  }
  return $self;
}

## add_accessor, adds an accessor to an object attribute.
sub add_accessor {
  my ($self, $attribute, $rw, $method) = @_;
  if (!$method) { $method = $attribute; }

  no strict 'refs'; ## just for this method.

  if ($rw) {
    *{$method} = sub {
      my $self = shift;
      if (@_) {
        if (@_ > 1) {
          $self->{$attribute} = [@_];
        }
        else {
          $self->{$attribute} = shift;
        }
        return $self;
      }
      else {
        return $self->{$attribute};
      }
    };
  }
  else {
    *{$method} = sub {
      my $self = shift;
      return $self->{$attribute};
    };
  }
}

## namespace, compatibility with Template::TAL
sub namespace { return }

## tags, compatibility with Template::TAL
sub tags { () }

## End of library
1;

