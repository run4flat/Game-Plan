# ABSTRACT: Edit a topic or planning module
use strict;
use warnings;

############################################################################
                   package App::gp::Command::edit;
############################################################################

use App::gp -command;
use Game::Plan::CurrRules;
use App::gp::EditTopic;
use Time::Piece;

sub usage_desc { '%c edit %o <topic|module.pm>' }

sub opt_spec {
	# Pull in the rules, for rule-specific options
	my $rules = App::gp->curr_rules;
	
	# Get stop options if the user is not already working on planning, in
	# which case this would terminate the previous task.
	my $curr_task = App::gp->curr_tasks->active;
	my @stop_options = (
		App::gp->stopstatus_options(),
		$rules->cmd_line_options('stop')
	) if $curr_task and $curr_task->{description} !~ /^Plan - /;
	
	# Collect and return the options
	return (
		$rules->cmd_line_options('edit'),
		@stop_options,
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	my $topic_name = $args->[0]
		or die "You must provide a topic or module name.\n";
	
	# Choose our file extensions
	$topic_name .= '.topic' unless $topic_name =~ /\.pm$/;
	
	# Make sure this file exist
	App::gp::Files::do_in_topics {
		die "File $topic_name does not exist\n" unless -f $topic_name;
	};
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# See if any rules have issues with me creating a new topic or module
	die "Not allowed to edit $topic_name\n"
		unless $rules->check(preedit => $topic_name, $opt);
	
	# Mark the previous task as stopped, unless it was a planning task
	my $made_changes = App::gp::EditTopic::edit($topic_name, $opt);
	
	if (not $rules->check(postedit => $topic_name, $made_changes, $opt) and $made_changes) {
		Game::Plan::Revision->rollback;
		die "Bad edit; rolling back to previous commit.\n"
	}
}

=head1 NAME

App::gp::Command::edit

=head1 VALIDATION RULES

Rule sets that want to effect to edit command can hook into the following
rules:

=over

=item preedit

Called before the user gets to edit the file. The
argument to the preedit rule is the topic file name. Failure of any rule
will prevent the user from editing the topic or module.

=item edit

Called after the user has finished editing the file, and only if the file
was changed. This rule is called with the topic file name. Failure of any
rule will prompt the user to re-edit the file or discard any changes.

=item postedit

Called after the user performs the edits, possibly after having made none,
or having failed to make the desired changes due to parse or rule errors.
The arguments to the postedit rule are the topic file name and a boolean
indicating whether changes were actually made to the topic. Failure of any
rule will cause the content of any edited files to be I<reverted to their
content>, without the option to re-edit. Therefore, only fail a postedit
rule when a harsh response is warranted.

=back

Rules can provide additional command-line keys under the rule name B<edit>.
If the user's currently active task is not a planning task (i.e. unless it
starts with C<Plan - ...>), the current task will also be stopped, and the
command-line options for stopping are also allowed.

=cut

1;
