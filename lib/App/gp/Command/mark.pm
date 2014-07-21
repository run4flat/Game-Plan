# ABSTRACT: Add a zero-duration entry to the timesheet with the given marking
use strict;
use warnings;

############################################################################
                  package App::gp::Command::mark;
############################################################################

use App::gp -command;
use Game::Plan::Timing;
use File::Slurp;
use Clone qw(clone);

sub usage_desc { '%c mark %o <description>' }
sub description { '    Prevents a recurring task from showing up for the rest of this day, by
    adding a zero-duration entry to the time sheet. Options include:
' }

sub opt_spec {
	# Pull in the rules, for rule-specific options
	my $rules = App::gp->curr_rules;
	return (
		App::gp->datetime_options,
		App::gp->stopstatus_options,
		$rules->cmd_line_options('mark'),
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	my $description = $args->[0] or die "You must provide a description.\n";
	
	# Replace the task description with the description from the last listing
	# if the description is purely numeric
	if ($description =~ /^\d+$/) {
		my @descriptions;
		App::gp::Files::do_in_data {
			croak('No previous task listing') unless -f 'list-cache';
			@descriptions = read_file('list-cache', {chomp => 1});
		};
		croak("You only have " . scalar(@descriptions) . " tasks from your last listing")
			if $description > @descriptions;
		# Offset by 1
		$description = $descriptions[$description-1];
		print "Marking \"$description\"\n";
	}
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# Get the time at which to mark the postponement
	my $time = Game::Plan::Timing::get_datetime($opt);
	
	# Hold on to the most recent task
	my $curr = $tasks->active;
	$tasks->pop if $curr;
	
	# Start and stop this task
	my $new = $tasks->start($description, $time);
	if (not $rules->check(start => $new, $opt)) {
		$tasks->pop;
		die "You are not allowed to mark (start) this task.\n";
	}
	$tasks->stop($time);
	if (not $rules->check(stop => $new, $opt, $description)) {
		$tasks->pop;
		die "You are not allowed to mark (stop) this task.";
	}
	else {
		$tasks->commit;
	}
	
	# Restore the most recent task to the top of the task list
	$tasks->push($curr) if $curr;
}

1;
