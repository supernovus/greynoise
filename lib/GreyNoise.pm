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

use Cwd qw(abs_path); ## Ensure our include dir is a full path.

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

## debug_obj: debugging tool, dumps things either as JSON or a string.
sub dump_obj {
  my $name = shift;
  my $object = shift;
  print "$name » ";
  if (ref $object) {
    print "JSON: ";
    say pretty_json($object);
  }
  else {
    print "String: ";
    say $object;
  }
}

## getById, works around the DTD limitations of getElementById()
sub getById {
  my ($doc, $id) = @_;
  return ($doc->findnodes("//*[\@id = '$id']"))[0];
}

#### Constructor

sub new {
  my $class = shift;
  my $config = shift;
  if (!-f $config) { die "config file '$config' not found"; }
  my $conf = decode_json(slurp($config));
  my $tal  = Template::TAL->new( 
    include_path => abs_path($conf->{templates}->{folder}),
#    input_format => 'HTML',
    output       => 'Template::TAL::Output::XML',
  );
  if ($conf->{templates}->{plugins}) { ## Template plugins.
    for my $plugin (@{$conf->{templates}->{plugins}}) {
#      say "Adding Template plugin '$plugin'";
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

## Accessors

sub conf {
  my $self = shift;
  return $self->{conf};
}

sub tal {
  my $self = shift;
  return $self->{tal};
}

sub pages {
  my ($self, $add) = @_;
  return $self->{pages} unless $add;
  $self->{pages}->{$add} = 1;
}

sub stories {
  my ($self, $add, $value) = @_;
  return $self->{stories} unless $add;
  $self->{stories}->{$add} = $value;
}

sub indexes {
  my ($self, $add, $value) = @_;
  return $self->{indexes} unless $add;
  $self->{indexes}->{$add} = $value;
}

sub cache {
  my ($self, $type, $id, $set) = @_;
  if ($set) {
    $self->{cache}->{$type}->{$id} = $set;
    return $self;
  }
  elsif ($id) {
    if (
         exists $self->{cache}->{$type} 
      && exists $self->{cache}->{$type}->{$id}
    ) {
      return $self->{cache}->{$type}->{$id};
    }
  }
  elsif ( $type && exists $self->{cache}->{$type} ) {
    return $self->{cache}->{$type};
  }
  return;
}

## Methods

sub add_page {
  my ($self, $file) = @_;
  if (!-f $file) { say "skipping missing page '$file'..."; return; }
  $self->pages($file);
}

sub add_story {
  my ($self, $cache, $file) = @_;
  if (!-f $file) { say "skipping missing story '$file'..."; return }
  $self->stories($file, $cache);
}

sub add_index {
  my ($self, $cache, $tag) = @_;
  if (!$tag) { $tag = 'index'; }
  $self->indexes($tag, $cache);
}

## The main routine to start this process.
sub generate {
  my $self = shift;
  for my $page (keys %{$self->pages}) {
    $self->build_page($page);
  }
  while ( my ($file, $cache) = each %{$self->stories} ) {
    $self->build_story($cache, $file);
  }
  while ( my ($tag, $cache) = each %{$self->indexes} ) {
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
  say "» Building page $file";
  my $page = $self->get_page($file);
  my $pagecontent = $self->parse_page($page);
#  say "Debugging!!!!!!!!!!!!!";
#  say $pagecontent;
#  say "!!!!!!!!!!!!!Debugging";
  my $outfile = $self->conf->{output} . $self->page_path($page);
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
  { no warnings;
    if (my $cache = $self->cache('cache', $file)) {
      return $cache;
    }
  }
  if (-f $file) {
    my $text = slurp($file);
    my $json = decode_json($text);
    $self->cache('cache', $file, $json);
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
  $self->cache('cache', $file, $data);
}

sub save_caches {
  my $self = shift;
  say "» Saving caches to disk";
  while (my ($file, $data) = each %{$self->cache('cache')}) {
    my $text = pretty_json($data); ## We want readable cache files.
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
  { no warnings;
    if (my $cache = $self->cache('date', $updated)) {
#      say "Returning cache for '$updated' datetime: $cache";
      return $cache;
    }
  }
  my $dt;
  if ($updated =~ /^\d+$/) { ## If we are an integer, assume Epoch value.
#    say "++ » Getting datetime from epoch";
    $dt = DateTime->from_epoch( 
      epoch => $updated, 
      formatter => DateTime::Format::Perl6->new()
    );
    $dt->set_time_zone('local'); ## Move into local-time AFTER parsing.
  }
  else {
#    say "++ » Getting datetime from perl6 string";
    my $parser = DateTime::Format::Perl6->new();
    $dt = $parser->parse_datetime($updated);
  }
  $self->cache('date', $updated, $dt);
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
    $self->cache('date', "$updated", $updated);
  }

  #say "Page XML » ".$page->{xml}->toString;

  #my $snippet = $page->{xml}->getElementById('snippet');
  my $snippet = getById($page->{xml}, 'snippet');
  if ($snippet) {
    $snippet = $snippet->cloneNode(1);
    $snippet->removeAttribute('id');
  }
  else {
#    say "» No snippet id was found, taking first <p/> element"; 
    my @ps = $page->{xml}->getElementsByTagName('p');
    if (@ps) {
      $snippet = $ps[0]->cloneNode(1);
    }
  }
#  say "snippet: ".$snippet->toString;

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
    'snippet'   => $snippet->toString,
  };

# say "… We got past the pagedef";

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

#  say "… We got past the tags";

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

#  say "… We got past chapter number and special fields";

  my $added = 0;
  my $smartlist = 1;
  if (exists $self->conf->{smartlist}) {
    $smartlist = $self->conf->{smartlist};
  }

#  say "» Starting the index placement routine...";

  my $ccount = @{$cache};

#  say " -- ccount: $ccount";

  if ($ccount > 0) {
    for (my $i=0; $i < $ccount; $i++) {
#      say "on count: $i";
      if ($cache->[$i] && $cache->[$i]->{link} eq $pagelink) {
        ## Kill the soup!
        splice(@{$cache}, $i--, 1);
        $ccount--; ## We're smaller now.
      }
      elsif ($smartlist) {
        if (!$added) {
          if ($story) {
            if (
              $cache->[$i]
              && exists $cache->[$i]->{chapter}
              && exists $pagedef->{chapter}
              && $cache->[$i]->{chapter} > $pagedef->{chapter}
            ) {
#            say "… we're a chapter, stick us in place.";
              splice(@{$cache}, $i, 0, $pagedef);
              $ccount++;
              $added = 1;
            }
          }
          elsif (
            $cache->[$i]
            && exists $cache->[$i]->{updated}
          ) {
#           say "… finding the date to put us in.";
            my $cdate = $self->get_datetime($cache->[$i]->{updated});
#            say "Comparing $updated and $cdate";
            if ($cdate < $updated) {
#              say "$updated is newer than $cdate";
              splice(@{$cache}, $i, 0, $pagedef);
              $ccount++;
              $added = 1;
            }
          }
        }
      }
    }
  }

#  say "… We got past index placement searches";

  ## If all else fails, fallback to default behaviour.
  if (!$added) {
#    say "» Apparently the page wasn't found, adding it now.";
    if ($smartlist || $story) {
#      say "… to the end of the list.";
      push(@{$cache}, $pagedef);
    }
    else {
#      say "… to the beginning of the list.";
      unshift(@{$cache}, $pagedef);
    }
  }

  $self->save_cache($cachefile, $cache);

#  say "… We got past cache saving";

  ## Queue up the story/index for building.
  if ($story) {
    say " … adding story build request for '$story'.";
    $self->add_story($cache, $story);
  }
  else {
    print " … adding index build request for ";
    if ($tag) { say "tag: '$tag'."; }
    else { say "site."; }
    $self->add_index($cache, $tag);
  }

#  say "We got to the end of add_to_list";

}

sub build_index {
  my ($self, $page, $index, $tag, $pagelimit) = @_;
  print "» Building index page $page ";
  if ($tag) { say "for tag '$tag'."; }
  else      { say "for site." }
  my $perpage;
  if ($pagelimit) { $perpage = $pagelimit; }
  elsif (exists $self->conf->{indexes}->{perpage}) {
    $perpage = $self->conf->{indexes}->{perpage};
  }
  else {
    $perpage = 10;
  }
  my $size = @{$index};
  my $from = ($perpage * $page) - $perpage;
  my $to   = ($perpage * $page) - 1;
  if ($to > $size) { $to = $size - 1; }
  my $pages = ceil($size / $perpage);
#  say "Pages: $pages";
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
  my $title;
  if ($tag) {
    $title = $tag;
  }
  elsif (exists $self->conf->{site}->{title}) {
    $title = $self->conf->{site}->{title};
  }
  else {
    $title = "Site Index";
  }
  my $pagedef = {
    'type' => 'index',
    'data' => {
      'count'    => $pages,
      'current'  => $page,
      'pager'    => \@pager,
      'items'    => \@items,
      'size'     => $size,
      'tag'      => $tag,
      'title'    => $title,
    },
  };

  my $content = $self->parse_page($pagedef);
  my $outfile = $self->conf->{output} . $self->index_path($page, $tag);
  $self->output_file($outfile, $content);

  if ($to < $size-1) {
    $self->build_index($page+1, $index, $tag, $perpage);
  }
}

sub build_story {
  my ($self, $index, $page) = @_;
  say "» Building story $page";
  my $story = $self->get_page($page);
  $story->{type} = 'story';
  $story->{data}->{items} = $index;
  $story->{data}->{size}  = @{$index};

  my $content = $self->parse_page($story);
  my $outfile = $self->conf->{output} . $self->story_path($page);
  $self->output_file($outfile, $content);
  $self->process_indexes($story);
}

sub get_page {
  my ($self, $file) = @_;
  my $parser = XML::LibXML->new();
  my $xml = $parser->parse_file($file);
  my $metadata = {};
  #my $node = $xml->getElementById('metadata');
  my $node = getById($xml, 'metadata');
  if (defined $node) {
    my $nodetext = $node->textContent;
    if ($nodetext) {
      $metadata = decode_json($nodetext);
    }
    $node->unbindNode();
  }
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
  if (exists $self->conf->{page}->{plugins}) {
    push @plugins, @{$self->conf->{page}->{plugins}};
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
    $metadata->{content} = $page->{xml}->cloneNode(1); # deep clone.
  }

  my $template = $self->conf->{templates}->{$type};
  ## The Template::TAL stuff is done in new rather than here.

  my $sitedata = {};
  if (exists $self->conf->{site}) {
    $sitedata = $self->conf->{site};
  }
  my $parsedata = {
    'site' => $sitedata,
    'page' => $metadata,
    '-app' => $self,     # some voodoo magic here.
  };

  my $pagecontent = $self->tal->process($template, $parsedata);
  ## Now we work around stupid fucking bugs which mean we can't
  ## put &copy; in a document, nor use © as the first gets 'expanded'
  ## and the second one gets corrupted. God Perl 5 has some issues.
  $pagecontent =~ s/\+\+(\w+)\+\+/&$1;/gsm;
  ## And finally, strip away all those stupid xmlns: tags which are
  ## now referencing stuff the webpage will never use.
  $pagecontent =~ s/\s*xmlns\:\w+=".*?"//g;
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
  make_path($self->conf->{output} . $folder);
}

## get-filename() has been replaced by basename() in this implementation.

## Paths for pages (articles and story chapters.)
sub page_path {
  my ($self, $page) = @_;
  my $file = $page->{file};
  { no warnings;
    if (my $cache = $self->cache('page', $file)) {
      return $cache;
    }
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
  $self->cache('page', $file, $outpath);
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
  { no warnings;
    if (my $cache = $self->cache('folder', $file)) {
      return $cache;
    }
  }
  my $filename = basename($file, ".xml");
  my $folder = "/stories/$filename";
  $self->cache('folder', $file, $folder);
  return $folder;
}

## The path for the story table of contents.
sub story_path {
  my ($self, $file) = @_;
  { no warnings;
    if (my $cache = $self->cache('page', $file)) {
      return $cache;
    }
  }
  my $folder = $self->story_folder($file);
  $self->make_output_path($folder);
  my $outpath = "$folder/index.html";
  $self->cache('page', $file, $outpath);
  return $outpath;
}

## Cache path for indexes, ported as per WhiteNoise.
sub index_cache {
  my ($self, $tag) = @_;
  if (!$tag) { $tag = 'index'; }
  my $dir = './cache/indexes';
  if (exists $self->conf->{indexes}->{folder}) {
    $dir = $self->conf->{indexes}->{folder};
  }
  make_path($dir);
  return "$dir/$tag.json";
}

## Cache path for stories.
sub story_cache {
  my ($self, $file) = @_;
  { no warnings;
    if (my $cache = $self->cache('story', $file)) {
      return $cache;
    }
  }
  my $filename = basename($file, ".xml");
  
  my $dir = './cache/stories';
  if (exists $self->conf->{stories}->{folder}) {
    $dir = $self->conf->{stories}->{folder};
  }
  make_path($dir);
  my $cachedir = "$dir/$filename.json";
  $self->cache('story', $file, $cachedir);
  return $cachedir;
}

sub load_plugin {
  my ($self, $module) = @_;
  { no warnings;
    if (my $cache = $self->cache('plugins', $module)) {
      return $cache;
    }
  }
  ## A big difference between this and WhiteNoise:
  ## We require full module namespaces. No shortcuts.
  $module->require or die "Can't load plugin '$module': $@";
  my $plugin = $module->new( engine => $self )
    or die "Couldn't initialize plugin '$module': $@";
  $self->cache('plugins', $module, $plugin);
  return $plugin;
}

#####################
1; # End of library #
   ##################