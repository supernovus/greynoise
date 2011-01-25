######################################
# GreyNoise: WhiteNoise for Perl 5   #
######################################

package GreyNoise;

### NOTE:
### A custom version of Template::TAL,
### as well as the sole distribution of DateTime::Format::Perl6
### are included in the "contrib" folder. They are requirements.

use v5.10;         ## I like Perl 5.10+
use JSON 2.0;      ## must have 2.0 or higher.
use Template::TAL; ## A TAL/METAL implementation.
use DateTime;      ## Dates for changelogs, etc.
use Slurp;         ## Just quick and simple.
use XML::LibXML;   ## Used for pages and page templates.
use Carp;          ## Useful for some functions.

use DateTime::Format::Perl6; ## Parser and Formatter for DateTime objects.

#### Subroutines

## Save pretty JSON: $text = pretty_json($object);
sub pretty_json {
  my $object = shift;
  my $text = JSON->new->utf8->pretty->encode($object);
  return $text;
}

#### Methods

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

## The main routine to start this process.
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

## A way to rebuild existing caches.
sub regenerate {
  my ($self, $index, $story) = @_;
  if (!$index) { $index = $self->index_cache(); }
  my @listing = @{$self->load_cache($index)};
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

sub build_page {
  my ($self, $file) = @_;
  my $page = $self->get_page($file);
  my $pagecontent = $self->parse_page($page);
  my $outfile = $self->{conf}->{output} . $self->page_page($page);
  $self->output_file($outfile, $pagecontent);
  if (exists($page->{data}->{parent})) {
    $self->process_story($page);
  }
  elsif (!$page->{data}->{noindex}) {
    $self->process_indexes($page);
  }
}

sub load_cache {
  my ($self, $file, $need) = @_;
  if (exists($self->{cache}->{cache}->{$file})) {
    return $self->{cache}->{cache}->{$file};
  }
  if (-f $file) {
    my $text = slurp($file);
    my $json = decode_json($text);
    $self->{cache}->{cache}->{$file} = $json;
    return $json;
  }
  elsif ($need) {
    die "cache file '$file' is missing.";
  }
  else {
    my $newcache = [];
    return $newcache;
  }
}

sub save_cache {
  my ($self, $file, $data) = @_;
  $self->{cache}->{cache}->{$file} = $data;
}

sub save_caches {
  while (my ($file, $data) = each %{$self->{cache}->{cache}}) {
    my $text = json_encode($data); # caches don't need pretty.
    $self->output_file($file, $text);
  }
}

sub process_story {
  my ($self, $page) = @_;
  $self->add_to_list($page, 'story', $page->{data}->{parent});
}

sub process_indexes {
  my ($self, $page) = @_;
  ## First, add it to the site index.
  $self->add_to_list($page);
  if (exists $page->{data}->{tags}) {
    for my $tag (@{$page->{data}->{tags}}) {
      $self->add_to_list($page, $tag);
    }
  }
}

sub get_datetime {
  my ($self, $updated) = @_;
  if (exists($self->{cache}->{date}->{$updated})) {
    return $self->{cache}->{date}->{$updated};
  }
  my $dt;
  if ($updated =~ /^\d+$/) { ## If we are an integer, assume Epoch value.
    $dt = DateTime.from_epoch( 
      epoch => $updated, 
      time_zone => 'local', 
      formatter => DateTime::Format::Perl6->new()
    );
  }
  else {
    my $parser = DateTime::Format::Perl6->new();
    $dt = $parser->parse_datetime($updated);
  }
  $self->{cache}->{date}->{$updated} = $dt;
  return $dt;
}

 

#####################
1; # End of library #
   ##################