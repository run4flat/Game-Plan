use strict;
use warnings;

############################################################################
                      package Game::Plan::Timing;
############################################################################

use Time::Piece;
use Time::ParseDate;
use Safe::Isa;

sub get_datetime {
	my $arg = shift;
	
	# Get the at argument if it's an options hash
	$arg = $arg->at if $arg->$_isa('Getopt::Long::Descriptive::Opts');
	
	# If the argument is undefined, default to right now.
	return scalar(localtime) if not defined $arg;
	
	# Otherwise, use Time::ParseDate
	my $seconds = parsedate($arg, PREFER_FUTURE => 1);
	die "Unable to parse `$arg'\n" unless defined $seconds;
	
	# Good to go, return our Time::Piece:
	return scalar(localtime($seconds));
}

my %letter_from_day = qw(
	Mon  M
	Tue  T
	Wed  W
	Thu  H
	Fri  F
	Sat  S
	Sun  U
);

sub letter_from_day {
	my ($time_piece) = @_;
	
	# Make sure we have a Time::Piece
	$time_piece = localtime(parsedate($time_piece))
		unless $time_piece->$_isa('Time::Piece');
	
	return $letter_from_day{$time_piece->day};
}

1;
