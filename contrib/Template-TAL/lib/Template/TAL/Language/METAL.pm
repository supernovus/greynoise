=head1 NAME

Template::TAL::Language::METAL - Implement METAL

=head1 SYNOPSIS

=head1 DESCRIPTION

This module is only partially implemented - it's here as a placeholder for the
METAL implementation. Currently, the define-macro and use-macro commands
are defined, but extend-macro, define-slot and fill-slot are not.
(http://www.zope.org/Wikis/DevSite/Projects/ZPT/METAL/MetalSpecification11)

=cut

package Template::TAL::Language::METAL;
use warnings;
use strict;
use Carp qw( croak );
use base qw( Template::TAL::Language );
use Template::TAL::ValueParser;

sub namespace { 'http://xml.zope.org/namespaces/metal' }

sub tags { qw( define-macro extend-macro use-macro define-slot fill-slot ) }

sub process_define_macro {
  my ($self, $parent, $node, $value, $local_context, 
      $global_context, $lid) = @_;
  if (!$lid) { $lid = 'DEFAULT'; }
  $self->{macros}{$lid}{ $value } = $node;
  #return (); # remove the macro definition node.
  return $node; ## supernovus says, I don't think we should remove node.
}

sub process_extend_macro {
  my ($self, $parent, $node, $value, $local_context, $global_context) = @_;
  return $node; # don't replace node
}

sub process_use_macro {
  my ($self, $parent, $node, $value, $local_context, 
      $global_context, $lid) = @_;
  if (!$lid) { $lid = 'DEFAULT'; }
  ## page support added by supernovus, based on my implementation from Flower.
  my $macro;
  if (exists $self->{macros}{$lid}{$value}) {
    $macro = $self->{macros}{$lid}{$value};
  }
  elsif ($value =~ /#/) {
    my @ns = split(/#/, $value, 2);
    my $section = $ns[1];
    if (exists $self->{macros}{$ns[0]}{$section}) {
      $macro = $self->{macros}{$ns[0]}{$section};
    }
    else {
      my $file = $parent->provider->get_template($ns[0]);
      my $parser = XML::LibXML->new();
      my $include = $parser->parse_file($file);
      if ($include) {
        $parent->_process_node(
          $include->documentElement, $local_context, $global_context,
          { $self->namespace => { 'define-macro' => 1, 'extend-macro' => 1 } },
          $ns[0]
        );
        if (exists $self->{macros}{$ns[0]}{$section}) {
          $macro = $self->{macros}{$ns[0]}{$section};
        }
        else {
          die "include file '$file' did not define macro '$section'.";
        }
      }
      else { die "couldn't parse include file '$file'."; }
    }
  }
  else {
    die "no such macro '$value'\n";
  }
  my $new = $macro->cloneNode(1); # deep clone
  $parent->_process_node( $new, $local_context, $global_context );
  return $new;
}

sub process_define_slot {
  my ($self, $parent, $node, $value, $local_context, $global_context) = @_;
  return $node; # don't replace node
}

sub process_use_slot {
  my ($self, $parent, $node, $value, $local_context, $global_context) = @_;
  return $node; # don't replace node
}

=back

=head1 COPYRIGHT

Written by Tom Insam, Copyright 2005 Fotango Ltd. All Rights Reserved

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=cut

1;
