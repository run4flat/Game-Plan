# ABSTRACT: Rename the currently running task
use strict;
use warnings;

############################################################################
                  package App::gp::Command::rename;
############################################################################

use App::gp -command;

sub description { '    Renames the current timesheet entry.
' }

sub execute {
	my ($self, $opt, $args) = @_;
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# Get the new description
	die "You must provide a new description\n" if @$args == 0;
	my $new_description = $args->[0];
	
	# Rename the current task, if there is one
	if (my $curr = $tasks->active) {
		# Make sure it's ok to rename
		die "You are not allowed to rename your current task.\n"
			if not $rules->check(rename => $curr, $new_description);
		my $old_description = $curr->{description};
		print "Renaming \"$old_description\" -> \"$new_description\"\n";
		$tasks->rename($new_description);
	}
	else {
		print "You are not tracking any tasks at the moment.\n";
	}
}

1;
