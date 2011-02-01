package GreyNoise::Pages::References;

use base qw( GreyNoise::Plugin );
use strict;
use warnings;

use XML::LibXML;

sub namespace { 'http://xml.huri.net/namespaces/refs'; }

sub parse {
  my ($self, $page) = @_;
  if (!exists $page->{xml}) { return; } ## skip non-pages.
  my $xml = $page->{xml};
  my @atags = $xml->getElementsByTagName('a');
  for my $atag (@atags) {
    my $refsite = undef;
    my $refterm = undef;
    for my $attribute ($atag->attributes) {
      my $uri = $attribute->getNameSpaceURI;
      next unless $uri and $attribute->nodetype == 2 
        and $uri eq $self->namespace; ## We only care about ref tags.
      if ($attribute->name eq 'site') {
        my $sitename = $attribute->value;
        $refsite = $self->engine->conf->{refs}->{$sitename};
      }
      elsif ($attribute->name eq 'site') {
        $refterm = $attribute->value;
      }
      ## TODO: remove the attribute.
    }
    if (defined $refsite) {
      if (!defined $refterm) {
        $refterm = $atag->textContent;
      }
      my $url = sprintf($refsite, $refterm);
      $atag->setAttribute('href', $url);
    }
  }
}

1;
