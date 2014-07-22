# ABSTRACT: Add a journal entry
use strict;
use warnings;

############################################################################
                  package App::gp::Command::journal;
############################################################################

use App::gp -command;
use Game::Plan::Timing;
use Time::Piece;
use File::Temp qw(tempfile);
use File::Slurp;
use App::gp::Files;

sub usage_desc { '%c journal %o' }
sub description { '    Edit your journal entry for the task with the given time, or create a new entry.
' }

sub opt_spec {
	# Pull in the rules, for rule-specific options
	my $rules = App::gp->curr_rules;
	return (
		App::gp->datetime_options,
		$rules->cmd_line_options('journal'),
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# Track the duration of the writing, in case it gets long
	my $start = localtime;
	
	# Get the time of the entry to find
	my $time = Game::Plan::Timing::get_datetime($opt);
	
	# Find the pre-existing entry in the time sheet
	my ($entry, $postponed) = $tasks->find(sub {
		$_->{start_time} <= $time and (
			not $_->{stop_time}
				or $time <= $_->{stop_time}
		)
	});
	$entry = $postponed if $postponed and not $entry;
	# If no entry but --at was given, then exit saying we couldn't find it
	die "Unable to locate entry from ", $opt->at, "\n"
		if not $entry and $opt->at;
	
	# Create a new entry if none exists
	my $task_name = $args->[0] || 'Journal';
	my $created = $entry = $tasks->start($task_name, $time) unless $entry;
	
	# Create temp file
	my ($fh, $filename) = tempfile('journal-XXXX');
	# write contents of $entry->{journal} to file
	print $fh $entry->{journal} if $entry->{journal};
	close $fh;
	# open in editor
	my $edit_cmd = $ENV{EDITOR} || 'nano';
	system($edit_cmd, $filename);
	# read contents back into $entry->{journal}
	$entry->{journal} = read_file($filename);
	# Remove the entry if it is blank
	delete $entry->{journal} if $entry->{journal} eq '';
	
	# Mark the stop of this journal editing if it is new
	if ($created) {
		$tasks->stop(scalar(localtime));
		$tasks->commit;
	}
	else {
		# Offer to add an entry to the timesheet if the time spent journaling
		# was lengthy.
	}
}

1;
