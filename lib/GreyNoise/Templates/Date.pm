## Not a full port of Flower::Util::Date, but a semi-compatible
## port of the strftime: modifier at least.
## As per GreyNoise (and WhiteNoise), it only supports
## date-stamps as epoch integers or Perl6-style datetime strings.
## It supports some premature-optimization in the form of the
## ability to directly use GreyNoise's get_datetime function.
## If and only if the $contexts[1]->{'-app'} exists, and does in
## fact have a get_datetime method.

package GreyNoise::Templates::Date;

use warnings;
use strict;
use base qw( GreyNoise::Plugin );
use v5.10;

use Template::TAL::ValueParser;
use DateTime;
use DateTime::Format::Perl6;

sub process_tales_strftime {
  my ($class, $string, $contexts, $plugins) = @_;

  my ($format, $lookup) = $string =~ /^'(.*?)'\s+(.*)$/;

  #say "format» $format";
  #say "lookup» $lookup";

  my $greynoise;
  if (exists $contexts->[1]->{'-app'}) {
    $greynoise = $contexts->[1]->{'-app'};
  }
  
  my $datetime = 
    Template::TAL::ValueParser->value($lookup, $contexts, $plugins);
  
  if (ref($datetime) ne 'DateTime') {
    if (defined $greynoise && $greynoise->can('get_datetime')) {
      $datetime = $greynoise->get_datetime($datetime);
    }
    else {
      if ($datetime =~ /^\d+$/) {
        $datetime = DateTime->from_epoch(
          epoch => $datetime,
          formatter => DateTime::Format::Perl6->new()
        );
        $datetime->set_time_zone('local');
      }
      else {
        my $parser = DateTime::Format::Perl6->new();
        $datetime = $parser->parse_datetime($datetime);
      }
    }
  }

  my $dtstring = $datetime->strftime($format);

  return $dtstring;
}

1;