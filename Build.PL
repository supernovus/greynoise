#!/usr/bin/perl
use warnings;
use strict;

use Module::Build;

Module::Build->new(
    dist_author => "Timothy Totten",
    module_name => 'GreyNoise',
    license => 'perl',
    requires => {
      'perl' => '5.010', # We use 5.10 specific features.
      'XML::LibXML' => 0,
      'Test::More' => 0,
      'Test::XML' => 0,
      'UNIVERSAL::require' => 0,
      'File::Find::Rule' => 0,
      'Slurp' => 0,
      'local::lib' => 0,
      'DateTime' => 0,
      'JSON' => '2.0',
      'version' => 0,
      'Template::TAL' => '0.10',
      'DateTime::Format::Perl6' => '1.0.0',
    },
    create_makefile_pl => 'traditional',
)->create_build_script;

