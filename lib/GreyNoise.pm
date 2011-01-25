######################################
# GreyNoise: WhiteNoise for Perl 5   #
######################################

package GreyNoise;

use v5.10;         ## I like Perl 5.10+
use JSON 2.0;      ## must have 2.0 or higher.
use Template::TAL; ## A TAL/METAL implementation.
use Date::Parse;   ## Parse date strings.
use Date::Format;  ## And format them again.
use Slurp;         ## Just quick and simple.
use XML::LibXML;   ## Used for pages and page templates.

sub new {
  my $class = shift;
  my $config = shift;
  if (!-f $config) { die "config file '$file' not found"; }
  my $conf = decode_json(slurp($config));
  my $tal  = Template::TAL->new( 
    include_path => $conf{templates}{dir},
    output       => 'Template::TAL::Output::XML',
  );
  if ($conf{templates}{plugins}) { ## Template plugins.
    for my $plugin (@{$conf{plugins}}) {
      require $plugin;
      $tal->add_language($plugin);
    }
  }
  my $data = {
    conf  => $conf,
    tal   => $tal,
    cache =>   { 
      cache   => {},
      page    => {},
      story   => {},
      folder  => {},
      index   => {},
      file    => {},
      date    => {},
      plugins => {}, ## Page plugins, not Template plugins.
    },
    pages   => {},
    stories => {},
    indexes => {},
  };
  return bless $data, $class;
}

sub add_page {
  my ($self, $file) = @_;
  if (!-f $file) { say "skipping missing page '$file'..."; return; }
  $self->{pages}->{$file} = 1;
}

sub add_story {
  my ($self, $cache, $file) = @_;
  if (!-f $file) { say "skipping missing story '$file'..."; return }
  $self->{stories}->{$file} = $cache;
}

sub add_index {
  my ($self, $cache, $tag) = @_;
  if (!$tag) { $tag = 'index'; }
  $self->{indexes}->{$tag} = $cache;
}

sub generate {
  my $self = shift;
  for my $page (keys %{$self->{pages}}) {
    $self->build_page($page);
  }
  while ( my ($file, $cache) = each %{$self->{stories}} ) {
    $self->build_story($cache, $file);
  }
  while ( my ($tag, $cache) = each %{$self->{stories}} ) {
    if ($tag eq 'index') {
      $self->build_index(1, $cache);
    }
    else {
      $self->build_index(1, $cache, $tag);
    }
  }
  $self->save_caches();
}

sub regenerate {
  my ($self, $index, $story) = @_;
  if (!$index) { $index = $self->index_cache(); }
  my @listing = $self->load_cache($index);
  if (!$story) {
    @listing = reverse(@listing);
  }
  for my $item (@listing) {
    if ($item->{type} eq 'article') {
      $self->add_page($item->{file});
    }
    elsif ($item->{type} eq 'story') {
      my $storycache = $self->story_cache($item->{file});
      $self->regenerate($storycache, 1);
    }
  }
}

#####################
1; # End of library #
   ##################