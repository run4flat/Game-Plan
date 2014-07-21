# ABSTRACT: Give a summary of the current activity
use strict;
use warnings;

############################################################################
                  package App::gp::Command::status;
############################################################################

use App::gp -command;
use App::gp::Files;
use Game::Plan::Timing;
use Time::Piece;
use Time::Seconds;

sub opt_spec {
	my $rules = App::gp->curr_rules;
	return (
		App::gp->datetime_options,
		App::gp->stopstatus_options,
		$rules->cmd_line_options('status'),
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# If there is a current task running, print out its details
	if (my $curr = $tasks->active) {
		# Get the time at which to potentially stop
		my $time = Game::Plan::Timing::get_datetime($opt);
		
		# Mark the current task as stopped
		$tasks->stop($time);
		
		# Get the task duration, in whole minutes
		my $duration = int($tasks->duration(0) / 60);
		
		my $started_at = $curr->{start_time}->strftime('%r');
		$started_at =~ s/^0+//;
		print "$curr->{description}  (for $duration minutes, started at $started_at)\n";
		
		# Perform "status" processing, which should be similar to "stop"
		# processing.
		$rules->check(status => $curr, $opt);
		
		# Get the awarded chance and points
		my ($chance, $points) = $rules->point_status($self, $curr);
		
		# Print to line up with the individual rule status printouts
		printf "  *%1.2f, +%-4d\n", $chance, $points;
		
		# "Resume" the task
		$tasks->unstop;
	}
	else {
		print "You are not tracking any activity at the moment.\n";
	}
	
	# Print out point totals for today
	my $midnight = localtime;
	$midnight -= $midnight->sec + $midnight->min * ONE_MINUTE
				+ $midnight->hour * ONE_HOUR;
	my $points_today = $tasks->point_total($midnight => scalar(localtime));
	
	print "Points earned today: $points_today\n";
}

1;
