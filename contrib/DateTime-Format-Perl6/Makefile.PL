use strict;
use warnings;

use ExtUtils::MakeMaker qw( WriteMakefile );

WriteMakefile(
   NAME          => 'DateTime::Format::Perl6',
   AUTHOR        => 'Timothy Totten <supernovus@gmail.com>',
   VERSION_FROM  => 'lib/DateTime/Format/Perl6.pm',
   ABSTRACT_FROM => 'lib/DateTime/Format/Perl6.pm',
   PREREQ_PM     => { 'DateTime'   => 0,
                      'Test::More' => 0,
                      'version'    => 0,
                    },
   dist          => { COMPRESS => 'gzip -9f', SUFFIX   => 'gz' },
   clean         => { FILES => 'DateTime-Format-Perl6-*' },
);
