# ABSTRACT: Stop tracking a task, and award points if finished
use strict;
use warnings;

############################################################################
                  package App::gp::Command::stop;
############################################################################

use App::gp -command;
use Game::Plan::Timing;

sub description { '    Stops tracking a current task. Planning rules can include their own options,
    so some of the options given below may depend upon the current task:
' }

sub opt_spec {
	my $rules = App::gp->curr_rules;
	return (
		App::gp->datetime_options,
		App::gp->stopstatus_options,
		$rules->cmd_line_options('stop'),
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# Get the time at which to start
	my $time = Game::Plan::Timing::get_datetime($opt);
	
	# Stop the current task, if there is one
	if (my $curr = $tasks->active) {
		$tasks->stop($time);
		if (not $rules->check(stop => $curr, $opt)) {
			$tasks->unstop;
			die "You are not allowed to stop your current task.\n";
		}
		else {
			$tasks->commit;
		}
	}
	else {
		print "You are not tracking any tasks at the moment.\n";
	}
}

1;
