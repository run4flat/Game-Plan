# ABSTRACT: Start tracking a task
use strict;
use warnings;

############################################################################
                  package App::gp::Command::start;
############################################################################

use App::gp -command;
use Game::Plan::Timing;
use File::Slurp;
use Clone qw(clone);

sub usage_desc { '%c start %o <description>' }
sub description { '    Starts tracking a new task. Options include:
' }

sub opt_spec {
	# Pull in the rules, for rule-specific options
	my $rules = App::gp->curr_rules;
	# Get stop options if this start would cause a stop
	my @stop_options = (
		App::gp->stopstatus_options,
		$rules->cmd_line_options('stop')
	) if App::gp->curr_tasks->active;
	return (
		App::gp->datetime_options,
		$rules->cmd_line_options('start'),
		@stop_options,
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
		print "Starting \"$description\"\n";
	}
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# Get the time at which to start
	my $time = Game::Plan::Timing::get_datetime($opt);
	
	# If we are about to stop the current task (before starting the new one),
	# kick off any rule actions for the stop
	if (my $curr = $tasks->active) {
		$tasks->stop($time);
		if (not $rules->check(stop => $curr, $opt, $description)) {
			$tasks->unstop;
			die "You are not allowed to stop your current task.";
		}
		else {
			$tasks->commit;
		}
	}
	
	# Start the new task, then apply the rules. Pop the task if the rules
	# don't allow it.
	my $curr = $tasks->start($description, $time);
	if (not $rules->check(start => $curr, $opt)) {
		$tasks->pop;
		die "You are not allowed to start this task.\n";
	}
}

1;
