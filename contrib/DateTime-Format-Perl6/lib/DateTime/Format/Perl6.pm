
package DateTime::Format::Perl6;

use strict;
use warnings;

use version; our $VERSION = qv('v1.0.0');

use Carp     qw( croak );
use DateTime qw( );

use constant FIRST_IDX   => 0;
use constant IDX_UC_ONLY => FIRST_IDX + 0;
use constant NEXT_IDX    => FIRST_IDX + 1;

sub new {
   my ($class, %opts) = @_;

   my $uc_only = delete( $opts{uc_only} );

   return bless([
      $uc_only,  # IDX_UC_ONLY
   ], $class);
}

sub parse_datetime {
   my ($self, $str) = @_;

   $self = $self->new()
      if !ref($self);

   $str = uc($str)
      if !$self->[IDX_UC_ONLY];
   
   my ($Y,$M,$D) = $str =~ s/^(\d{4})-(\d{2})-(\d{2})// && (0+$1,0+$2,0+$3)
       or croak("Incorrectly formatted date");

   $str =~ s/^T//
      or croak("Incorrectly formatted datetime");

   my ($h,$m,$s) = $str =~ s/^(\d{2}):(\d{2}):(\d{2})// && (0+$1,0+$2,0+$3)
       or croak("Incorrectly formatted time");

   my $ns = $str =~ s/^\.(\d{1,9})\d*// ? 0+substr($1.('0'x8),0,9) : 0;

   my $tz;
   if    ( $str =~ s/^Z//                     ) { $tz = 'UTC';    }
   elsif ( $str =~ s/^([+-])(\d{2}):?(\d{2})// ) { $tz = "$1$2$3"; }
   else { croak("Missing time zone"); }

   $str =~ /^\z/ or croak("Incorrectly formatted datetime");

   return DateTime->new(
      year       => $Y,
      month      => $M,
      day        => $D,
      hour       => $h,
      minute     => $m,
      second     => $s,
      nanosecond => $ns,
      time_zone  => $tz,
      formatter  => $self,
   );
}


sub format_datetime {
   my ($self, $dt) = @_;

   my $tz;
   if ($dt->time_zone()->is_utc()) {
      $tz = 'Z';
   } else {
      my $secs  = $dt->offset();
      my $sign = $secs < 0 ? '-' : '+';  $secs = abs($secs);
      my $mins  = int($secs / 60);       $secs %= 60;
      my $hours = int($mins / 60);       $mins %= 60;
      if ($secs) {
         ( $dt = $dt->clone() )
            ->set_time_zone('UTC');
         $tz = 'Z';
      } else {
         $tz = sprintf('%s%02d%02d', $sign, $hours, $mins);
      }
   }

   return $dt->strftime('%Y-%m-%dT%H:%M:%S').$tz;
}

1;


__END__

=head1 NAME

DateTime::Format::Perl6 - Parse and format Perl6-style datetime strings


=head1 VERSION

Version 1.0.0


=head1 SYNOPSIS

    use DateTime::Format::Perl6;

    my $f = DateTime::Format::Perl6->new();
    my $dt = $f->parse_datetime( '2002-07-01T13:50:05-0800' );

    # 2002-07-01T13:50:05-0800
    print $f->format_datetime($dt);


=head1 DESCRIPTION

This module understands the Perl 6 date/time format, an ISO 8601 profile,
defined at L<http://perlcabal.org/syn/S32/Temporal.html>.

It can be used to parse that format in order to create the appropriate 
objects.


=head1 METHODS

=over

=item C<parse_datetime($string)>

Given a Perl 6 datetime string, this method will return a new
L<DateTime> object.

If given an improperly formatted string, this method will croak.

For a more flexible parser, see L<DateTime::Format::ISO8601>.

=item C<format_datetime($datetime)>

Given a L<DateTime> object, this methods returns a Perl 6 datetime
string.

=back

=head1 SEE ALSO

=over 4

=item * L<DateTime>

=item * L<DateTime::Format::ISO8601>

=item * L<DateTime::Format::RFC3339>, the module that was forked from.

=item * L<http://perlcabal.org/syn/S32/Temporal.html>, Perl 6 Temporal specification, from where this date format is specified.

=back


=head1 BUGS

Please report any bugs to the author (see below.)

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DateTime::Format::Perl6


=head1 AUTHOR

Timothy Totten, C<< <supernovus@gmail.com> >>, the guy who hacked this up using an existing module as a basis.

Eric Brine, C<< <ikegami@adaelis.com> >>, author of DateTime::Format::RFC3339, which this is based on.


=head1 COPYRIGHT & LICENSE

Public domain. No rights reserved.


=cut
