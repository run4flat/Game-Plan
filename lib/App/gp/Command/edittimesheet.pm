# ABSTRACT: Edit the current, unarchived time sheet
use strict;
use warnings;

############################################################################
                  package App::gp::Command::edittimesheet;
############################################################################

use App::gp -command;
use App::gp::Files;
use File::Slurp;
use JSON;
use Time::Piece;

sub opt_spec {
	# Pull in the rules, for rule-specific options
	my $rules = App::gp->curr_rules;
	
	# Collect and return the options
	return (
		$rules->cmd_line_options('edittimesheet'),
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	
	# Only allow edits if the file exists
	my $ts_file = App::gp::Files->ts;
	if (not -f $ts_file) {
		print "No time sheet file to edit.\n";
		return;
	}
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	die "You are not allowed to edit the time sheet.\n"
		if not $rules->check('edittimesheet', $opt);
	
	# Load the data (i.e. back it up)
	my $backup = read_file($ts_file);
	
	my $repeat = 1;
	while($repeat) {
		# Edit the file
		my $edit_cmd = $ENV{EDITOR} || 'nano';
		system($edit_cmd, $ts_file);
		
		# Slurp in the edits
		my $json_text = read_file($ts_file);
		
		# make sure it parses  working here
		eval {
			my $new_timesheet = decode_json($json_text);
			$repeat = 0;
			@{App::gp->curr_tasks} = @$new_timesheet;
			1;
		}
		or do {
			# Failed to parse. Allow the user to manually recover
			$@ =~ s/\.\.\."\) at .*\n/...)/;  # clean up the message
			print "Invalid JSON: $@\n";
			my $input = prompt_str('Edit again or discard changes?', {
				valid => sub { $_[0] =~ /^[ex]$/i },
				default => 'e',
				choices => 'E/x',
			});
			
			if ($input eq 'x') {
				# restore from our backup
				write_file($ts_file, $backup);
				$repeat = 0;
			}
			# Default behavior will loop back into the editor
		};
	}
}

1;
