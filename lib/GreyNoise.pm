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
use POSIX;         ## We're using ceil().

use UNIVERSAL::require; ## A quick way to load plugins.

use File::Basename;            ## Better than get-filename from WhiteNoise.
use File::Path qw(make_path);  ## make_path is useful.

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
    include_path => $conf->{templates}->{folder},
    output       => 'Template::TAL::Output::XML',
  );
  if ($conf->{templates}->{plugins}) { ## Template plugins.
    for my $plugin (@{$conf->{plugins}}) {
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
    $cachefile = $self->index_cache($tag);
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
      if ($section =~ /(link|title|updated|snippet|tags|content)/) {
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

  if (@{$cache} > 0) {
    for (my $i=0; $i < @{$cache}; $i++) {
      if ($cache->[$i]->{link} eq $pagelink) {
        if ($story) {
          splice(@{$cache}, $i, 1, $pagedef);
          $added = 1;
          last;
        }
        else {
          splice(@{$cache}, $i, 1);
        }
      }
      elsif ($smartlist) {
        if (
          $story
          && exists $cache->[$i]->{chapter}
          && exists $pagedef->{chapter}
          && $cache->[$i]->{chapter} > $pagedef->{chapter}
        ) {
          splice(@{$cache}, $i, 0, $pagedef);
          $added = 1;
        }
        elsif (
          !$story
          && !$added
          && exists $cache->[$i]->{updated}
        ) {
          my $cdate = $self->get_datetime($cache->[$i]->{updated});
          if ($cdate < $updated) {
            splice(@{$cache}, $i, 0, $pagedef);
            $added = 1;
          }
        }
      }
    }
  }
  ## If all else fails, fallback to default behaviour.
  if (!$added) {
    if ($story) {
      push(@{$cache}, $pagedef);
    }
    else {
      unshift(@{$cache}, $pagedef);
    }
  }

  $self->save_cache($cachefile, $cache);

  ## Queue up the story/index for building.
  if ($story) {
    $self->add_story($cache, $story);
  }
  else {
    $self->add_index($cache, $tag);
  }

}

sub build_index {
  my ($self, $page, $index, $tag, $pagelimit) = @_;
  my $perpage;
  if ($pagelimit) { $perpage = $pagelimit; }
  elsif (exists $self->{conf}->{indexes}->{perpage}) {
    $perpage = $self->{conf}->{indexes}->{perpage};
  }
  else {
    $perpage = 10;
  }
  my $from = ($perpage * $page) - $perpage;
  my $to   = ($perpage * $page) - 1;
  if ($to > @{$index}) { $to = @{$index}; }
  my $pages = ceil(@{$index} / $perpage);
  my @items = @{$index}[ $from .. $to ];
  my @pager;
  for my $pagecount ( 1 .. $pages ) {
    my $pagelink = $self->index_path($pagecount, $tag);
    my $current = 0;
    if ($pagecount == $page) { $current = 1; }
    my $pagerdef = {
      'num'     => $pagecount,
      'link'    => $pagelink,
      'current' => $current,
    };
    push(@pager, $pagerdef);
  }
  my $pagedef = {
    'type' => 'index',
    'data' => {
      'count'    => $pages,
      'current'  => $page,
      'pager'    => \@pager,
      'items'    => $index,
      'size'     => @{$index},
      'tag'      => $tag,
    },
  };

  my $content = $self->parse_page($pagedef);
  my $outfile = $self->{conf}->{output} . $self->index_path($page, $tag);
  $self->output_file($outfile, $content);

  if ($to < @{$index}) {
    $self->build_index($page+1, $index, $tag, $perpage);
  }
}

sub build_story {
  my ($self, $index, $page) = @_;
  my $story = $self->get_page($page);
  $story->{type} = 'story';
  $story->{data}->{items} = $index;
  $story->{data}->{size}  = @{$index};

  my $content = $self->parse_page($story);
  my $outfile = $self->{conf}->{output} . $self->story_path($page);
  $self->output_file($outfile, $content);
  $self->process_indexes($story);
}

sub get_page {
  my ($self, $file) = @_;
  my $parser = XML::LibXML->new();
  my $xml = $parser->parse_file($file);
  my $metadata = {};
  my $node = $xml->getElementById('metadata');
  my $nodetext = $node->textContent;
  if ($nodetext) {
    $metadata = decode_json($nodetext);
  }
  $node->unbindNode();
  my $page = {
    'file'   => $file,
    'xml'    => $xml,
    'data'   => $metadata,
  };
  return $page;
}

sub parse_page {
  my ($self, $page) = @_;
  my @plugins;
  if (exists $self->{conf}->{page}->{plugins}) {
    push @plugins, @{$self->{conf}->{page}->{plugins}};
  }
  if (exists $page->{data}->{plugins}) {
    push @plugins, @{$page->{data}->{plugins}};
  }
  for my $module (@plugins) {
    my $plugin = $self->load_plugin($module);
    $plugin->parse($page);
  }

  my $metadata = $page->{data};
  my $type = 'article';
  if (exists $page->{type}) {
    $type = $page->{type};
  }

  ## make "page/content" into the XML node(s), if this is a page.
  if (exists $page->{xml}) {
    ## Because of our modifications to Template::TAL, we can do this:
    $metadata->{content} = $page->{xml};
  }

  my $template = $self->{conf}->{templates}->{$type};
  ## The Template::TAL stuff is done in new rather than here.

  my $sitedata = {};
  if (exists $self->{conf}->{site}) {
    $sitedata = $self->{conf}->{site};
  }
  my $parsedata = {
    'site' => $sitedata,
    'page' => $metadata,
  };

  my $pagecontent = $self->{tal}->process($template, $parsedata);
  return $pagecontent;
}

## Spit out a file.
sub output_file {
  my ($self, $file, $content) = @_;
  open (my $fh, '>', $file);
  say $fh $content;
  close ($fh);
  say " -- Generated file: '$file'.";
}

## Create output folders.
sub make_output_path {
  my ($self, $folder) = @_;
  make_path($self->{conf}->{output} . $folder);
}

## get-filename() has been replaced by basename() in this implementation.

## Paths for pages (articles and story chapters.)
sub page_path {
  my ($self, $page) = @_;
  my $file = $page->{file};
  if (exists $self->{cache}->{page}->{$file}) {
    return $self->{cache}->{page}->{$file};
  }
  my $opts = $page->{data};
  my $filename = basename($file, ".xml");

  my $dir;
  if (exists $opts->{parent}) {
    $dir = $self->story_folder($opts->{parent});
  }
  else {
    $dir = '/articles';
    if (!$opts->{toplevel}) {
      my $date = 0;
      if (exists $opts->{updated}) {
        $date = $opts->{updated};
      }
      elsif (exists $opts->{changelog}) {
        my $cl = $opts->{changelog};
        my $last = $cl->[-1];
        $date = $last->{date};
      }
      if ($date) {
        my $dt = $self->get_datetime($date);
        my $year = $dt->year;
        my $month = sprintf('%02d', $dt->month);
        $dir .= "/$year/$month";
      }
    }
  }
  $self->make_output_path($dir);
  my $outpath = "${dir}/${filename}.html";
  $self->{cache}->{page}->{$file} = $outpath;
  return $outpath;
}

## Paths for indexes, not cached, as per WhiteNoise.
sub index_path {
  my ($self, $page, $tag) = @_;
  if (!$page) { $page = 1; }
  my $dir = '/';
  if ($tag) {
    $dir = "/tags/$tag/";
  }
  elsif ($page > 1) {
    $dir = "/index/";
  }
  $self->make_output_path($dir);
  my $file = 'index.html';
  if ($page > 1) {
    $file = "page${page}.html";
  }
  my $outpath = $dir . $file;
  return $outpath;
}

## Story paths are used both for the story index
## and the story pages. Here is the common version.
sub story_folder {
  my ($self, $file) = @_;
  if (exists $self->{cache}->{folder}->{$file}) {
    return $self->{cache}->{folder}->{$file};
  }
  my $filename = basename($file, ".xml");
  my $folder = "/stories/$filename";
  $self->{cache}->{folder}->{$file} = $folder;
  return $folder;
}

## The path for the story table of contents.
sub story_path {
  my ($self, $file) = @_;
  if (exists $self->{cache}->{page}->{$file}) {
    return $self->{cache}->{page}->{$file};
  }
  my $folder = $self->story_folder($file);
  $self->make_output_path($folder);
  my $outpath = "$folder/index.html";
  $self->{cache}->{page} = $outpath;
  return $outpath;
}

## Cache path for indexes, ported as per WhiteNoise.
sub index_cache {
  my ($self, $tag) = @_;
  if (!$tag) { $tag = 'index'; }
  my $dir = './cache/indexes';
  if (exists $self->{conf}->{indexes}->{folder}) {
    $dir = $self->{conf}->{indexes}->{folder};
  }
  make_path($dir);
  return "$dir/$tag.json";
}

## Cache path for stories.
sub story_cache {
  my ($self, $file) = @_;
  if (exists $self->{cache}->{story}->{$file}) {
    return $self->{cache}->{story}->{$file};
  }
  my $filename = basename($file, ".xml");
  
  my $dir = './cache/stories';
  if (exists $self->{conf}->{stories}->{folder}) {
    $dir = $self->{conf}->{stories}->{folder};
  }
  make_path($dir);
  my $cachedir = "$dir/$filename.json";
  $self->{cache}->{story}->{$file} = $cachedir;
  return $cachedir;
}

sub load_plugin {
  my ($self, $module) = @_;
  if (exists $self->{cache}->{plugins}->{$module}) {
    return $self->{cache}->{plugins}->{$module};
  }
  ## A big difference between this and WhiteNoise:
  ## We require full module namespaces. No shortcuts.
  $module->require or die "Can't load plugin '$module': $@";
  my $plugin = $module->new or die "Couldn't initialize plugin '$module': $@";
  $plugin->{engine} = $self; ## Add ourself to the plugin.
  $self->{cache}->{plugins} = $plugin;
  return $plugin;
}

#####################
1; # End of library #
   ##################