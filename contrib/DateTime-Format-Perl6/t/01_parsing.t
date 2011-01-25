#!perl -T

use strict;
use warnings;

use DateTime                qw( );
use DateTime::Format::Perl6 qw( );

my @pos_tests;
my @neg_tests;
BEGIN {
   @pos_tests = (
      [
         '2002-07-01T13:50:05Z',
         DateTime->new( year => 2002, month => 7, day => 1, hour => 13, minute => 50, second => 5, time_zone => 'UTC' ),
      ],
      [
         '2002-07-01T13:50:05.123Z',
         DateTime->new( year => 2002, month => 7, day => 1, hour => 13, minute => 50, second => 5, nanosecond => 123000000, time_zone => 'UTC' ),
      ],
      [
        '2011-01-25T15:42:17-0800',
        DateTime->new( year => 2011, month => 1, day => 25, hour => 15, minute => 42, second => 17, time_zone => '-0800' ),
      ],
   );

   @neg_tests = (
   );
}

use Test::More tests => @pos_tests + @neg_tests;

for (@pos_tests) {
   my ($str, $expected_dt) = @$_;
   my $actual_dt = eval { DateTime::Format::Perl6->parse_datetime($str) };
   ok( defined($actual_dt) && $actual_dt eq $expected_dt, $str );
}

for (@neg_tests) {
   my ($str, $expected_e) = @$_;
   eval { DateTime::Format::Perl6->parse_datetime($str) };
   my $actual_e = $@;
   like( $actual_e, $expected_e, $str );
}

