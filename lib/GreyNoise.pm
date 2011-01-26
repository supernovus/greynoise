######################################
# GreyNoise: WhiteNoise for Perl 5   #
######################################

=head1 NAME

GreyNoise - A static website generator based on WhiteNoise

=head1 SYNOPSIS

  $ greynoise --page ./site-config.json ./pages/my-page.xml

=head1 DESCRIPTION

See the README, I haven't ported it into the POD docs yet.

=cut

package GreyNoise;

our $VERSION = "0.01";

### NOTE:
### A custom version of Template::TAL,
### as well as the sole distribution of DateTime::Format::Perl6
### are included in the "contrib" folder. They are requirements.

use strict;
use warnings;
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
  if (!-f $config) { die "config file '$config' not found"; }
  my $conf = decode_json(slurp($config));
  my $tal  = Template::TAL->new( 
    include_path => $conf->{templates}->{dir},
    output       => 'Template::TAL::Output::XML',
  );
  if ($conf->{templates}->{plugins}) { ## Template plugins.
    for my $plugin (@{$conf->{plugins}}) {
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
  my $self = shift;
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
    $dt = DateTime->from_epoch( 
      epoch => $updated, 
      formatter => DateTime::Format::Perl6->new()
    );
    $dt->set_time_zone('local'); ## Move into local-time AFTER parsing.
  }
  else {
    my $parser = DateTime::Format::Perl6->new();
    $dt = $parser->parse_datetime($updated);
  }
  $self->{cache}->{date}->{$updated} = $dt;
  return $dt;
}

sub add_to_list {
  my ($self, $page, $tag, $story) = @_;
  my $cachefile;
  if ($story) {
    $cachefile = $self->story_cache($story);
  }
  else {
    $cachfile = $self->index_cache($tag);
  }
  my $cache = $self->load_cache($cachefile);
  my $pagelink = $self->page_path($page);
  my $pagedata = $page->{data};

  my $updated;
  if (exists $pagedata->{updated}) {
    $updated = $self->get_datetime($pagedata->{updated});
  }
  elsif (exists $pagedata->{changelog}) {
    my $newest = $pagedata->{changelog}->[0]->{date};
    $updated = $self->get_datetime($newest);
  }
  elsif (exists $pagedata->{items}) {
    my $pageitems = $pagedata->{items};
    my $lastitem  = $pageitems->[-1];
    my $lastdate  = $lastitem->{updated};
    $updated = $self->get_datetime($lastdate);
  }
  else {
    $updated = DateTime->now();
    $updated->set_time_zone('local');
    $self->{cache}->{date}->{"$updated"} = $updated;
  }

  my $snippet = $page->{xml}->getElementById('snippet');
  if (!$snippet) {
    $snippet = $page->{xml}->documentElement->firstChild;
  }

  my $type = 'article';
  if (exists $page->{type}) {
    $type = $page->{type};
  }

  my $pagedef = {
    'type'      => $type,
    'file'      => $page->{file},
    'link'      => $pagelink,
    'title'     => $pagedata->{title},
    'updated'   => "$updated",
    'snippet'   => $snippet->toString(),
  };

  ## Lets add any tag links.
  if (exists $pagedata->{tags}) {
    my @tags;
    for my $pagetag (@{$pagedata->{tags}}) {
      my $taglink = $self->index_path(1, $pagetag);
      my $tagdef = {
        'name'  => $pagetag,
        'link'  => $taglink,
      };
      push(@tags, $tagdef);
      $pagedef->{tags} = \@tags;
    }
  }

  ## Add a chapter number, if it exists.
  if (exists $pagedata->{chapter}) {
    $pagedef->{chapter} = $pagedata->{chapter};
  }

  ## Special fields to index.
  if (exists $pagedata->{index}) {
    for my $section (@{$pagedata->{index}}) {
      if ($section ~= /(link|title|updated|snippet|tags|content)/) {
        next; ## Skip non-overridable sections.
      }
      if (exists $pagedata->{$section}) {
        $pagedef->{$section} = $pagedata->{$section};
      }
    }
  }

  my $added = 0;
  my $smartlist = 1;
  if (exists $self->{conf}->{smartlist}) {
    $smartlist = $self->{conf}->{smartlist};
  }

##### WE ARE HERE!

}
#####################
1; # End of library #
   ##################