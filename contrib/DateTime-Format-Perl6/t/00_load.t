#!perl -T

use strict;
use warnings;

use Test::More tests => 1;

BEGIN { require_ok( 'DateTime::Format::Perl6' ); }

diag( "Testing DateTime::Format::Perl6 $DateTime::Format::Perl6::VERSION, Perl $]" );

