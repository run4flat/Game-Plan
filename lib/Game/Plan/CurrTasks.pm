=head1 NAME

Game::Plan::CurrTasks - Manage the current tasks

=head1 SYNOPSIS

 use Game::Plan::CurrTasks;
 
 my $tasks = Game::Plan::CurrTasks->new;
 
 my $active = $tasks->active;
 if ($active) {
   print "Current task started at $active->{hour}:$active->{min}\n";
 }
 
 # Create a new task
 $tasks->start($description => $start_time_piece);
 
 # Tasks are auto-saved when the object goes out of scope

=cut

############################################################################
                      package Game::Plan::CurrTasks;
############################################################################

use strict;
use warnings;
use App::gp::Files;
use JSON;
use File::Slurp;
use Time::Piece;
use Time::ParseDate;
use Carp;

sub new {
	# No timesheet => empty array
	return return bless [] unless -f App::gp::Files->ts;
	
	# Empty timesheet => empty array
	my $json_text = read_file(App::gp::Files->ts);
	return bless [] unless $json_text;
	
	# Timesheet => json parse
	return bless scalar(JSON->new->filter_json_single_key_object(
		__time_piece__ => sub {
			my $string = shift;
			my $seconds = parsedate($string);
			die "Unable to parse date `$string' in " . App::gp::Files->ts . " line $.\n"
				if not defined $seconds;
			return scalar(localtime($seconds));
		}
	)->decode($json_text));
}

# Corresponding to the time decoder above, here is the JSON encoder for
# Time::Piece
sub Time::Piece::TO_JSON { return { __time_piece__ => $_[0]->strftime('%r %F') } }

sub DESTROY {
	my $self = shift;
	
	# If we've reached this point and there is a backup, then restore the
	# backup (could happen if the program dies in mid-processing)
	$self->[0] = $self->[0]{_backup}
		if @$self > 0 and exists $self->[0]{_backup};
	
	# Can't use File::Slurp since this may be called during global
	# destruction; since File::Slurp consults %!, and since that variable
	# may have been destroyed, I have to open the file manually.
	open my $out_fh, '>', App::gp::Files->ts;
	print $out_fh JSON->new->allow_blessed->convert_blessed->pretty->encode([@$self]);
	close $out_fh;
}

sub active {
	my $self = shift;
	# Return an undefined value if there are no tasks, or the latest task is
	# not an active one.
	return if @$self == 0 or exists $self->[0]{stop_time};
	# Return the latest task
	return $self->[0];
}

sub duration {
	my ($self, $offset) = @_;
	return if @$self <= $offset;
	return if not exists $self->[$offset]{start_time}
		or not exists $self->[$offset]{stop_time};
	return $self->[$offset]{stop_time} - $self->[$offset]{start_time};
}

sub start {
	my ($self, $description, $start_time) = @_;
	
	# Handle the currently active task, if applicable
	$self->stop($start_time);
	
	# Add the new task
	unshift @$self, {
		description => $description,
		start_time => $start_time,
	};
	return $self->[0];
}

sub stop {
	my ($self, $stop_time) = @_;
	# Can only stop an active task (return false if nothing was stopped)
	return unless my $active = $self->active;
	# Make sure the stop comes after the start
	croak('Stop time must be after start time')
		if $stop_time < $active->{start_time};
	# Back up this state, in case of unstop, *before* storing the stop time
	$active->{_backup} = {%$active};
	# Store stop time, return the newly stopped task
	$active->{stop_time} = $stop_time;
	return $self->[0];
}

sub unstop {
	my $self = shift;
	# Can only unstop if our most recent task is inactive
	return if @$self == 0 or $self->active;
	
	# Restore from backup
	return $self->[0] = $self->[0]{_backup} if exists $self->[0]{_backup};
	
	# Complain if no backup
	carp('Attempting to unstop a task which has no backup');
	return $self->[0];
}

sub commit {
	my $self = shift;
	# Can only commit if our most recent task is inactive
	return if @$self == 0 or $self->active;
	
	# Remove backup
	delete $self->[0]{_backup};
	
	# Mark the task as completed
	if ($self->[0]{finished}) {
		App::gp->curr_rules->mark_as_completed($self->[0], '+');
	}
	elsif ($self->[0]{canceled}) {
		App::gp->curr_rules->mark_as_completed($self->[0], 'x');
	}
	
	return $self->[0];
}

sub reset {
	my ($self, $start_time) = @_;
	return unless my $active = $self->active;
	$active->{start_time} = $start_time;
	return $self->[0];
}

sub pop {
	my ($self) = @_;
	# Remove the most recent (and possibly active) task
	return shift(@$self);
}

sub push {
	my ($self, $task) = @_;
	unshift @$self, $task if $task;
}

# Find first task that matches the given pattern.
sub find {
	my ($self, $pattern, $start) = @_;
	return unless defined $pattern;
	
	my $i = $start || 0;
	
	my ($postponed, $task, $eval_subref);
	
	# if a simple scalar (string) was supplied...
	if (not ref($pattern)) {
		$eval_subref = sub { $pattern eq $task->{description} };
	}
	# If a regex was supplied...
	elsif (ref($pattern) eq ref(qr//)) {
		$eval_subref = sub { $task->{description} =~ $pattern };
	}
	# if a subroutine referece was given...
	elsif (ref($pattern) eq ref(sub{})) {
		$eval_subref = $pattern;
	}
	# Otherwise I don't know what to do
	else {
		croak("You must provide a string or regex ref as your pattern");
	}
	
	# Run through each item and check
	for my $t (@$self) {
		$task = $t;
		if ($eval_subref->()) {
			if ($task->{postponed} and not $postponed) {
				$postponed = $task;
			}
			else {
				return ($task, $postponed);
			}
		}
	}
	return (undef, $postponed);
}

1;

