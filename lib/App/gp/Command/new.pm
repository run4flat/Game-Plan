# ABSTRACT: Create a new topic or planning module
use strict;
use warnings;

############################################################################
                   package App::gp::Command::new;
############################################################################

use App::gp -command;
use App::gp::Files;
use App::gp::EditTopic;
use File::Slurp;
use Time::Piece;

sub description { '    Creates a new planning topic or module. Options include:
' }
sub usage_desc { '%c new %o <topic|module.pm>' }

# New file templates, defined at the bottom of this module
my ($new_topic_contents, $new_module_contents);

sub opt_spec {
	# Pull in the rules, for rule-specific options
	my $rules = App::gp->curr_rules;
	
	# Collect and return the options
	return (
		[ 'noedit', 'create the topic or module, but do not edit it', ],
		$rules->cmd_line_options('new'),
		$rules->cmd_line_options('edit'),
	);
}
sub execute {
	my ($self, $opt, $args) = @_;
	my $topic_name = $args->[0]
		or die "You must provide a name for your topic or module.\n";
	
	# Choose our file extensions
	$topic_name .= '.topic' unless $topic_name =~ /\.pm$/;
	
	# Make sure this file does not already exist
	App::gp::Files::do_in_topics {
		die "File $topic_name already exists\n" if -f $topic_name;
	};
	
	my $tasks = App::gp->curr_tasks;
	my $rules = App::gp->curr_rules;
	
	# See if any rules have issues with me creating a new topic or module
	die "Not allowed to create $topic_name\n"
		unless $rules->check(new => $topic_name, $opt);
	
	App::gp::Files::do_in_topics {
		# Create the new file, and edit it
		if ($topic_name =~ /\.pm$/) {
			write_file($topic_name, $new_module_contents);
		}
		else {
			write_file($topic_name, $new_topic_contents);
		}
	};
	
	# Check-in and return if they don't want to actually edit it
	return Game::Plan::Revision->do_and_commit(sub {1}) if $opt->noedit;
	
	my $made_changes = App::gp::EditTopic::edit($topic_name, $opt);
	
	if (not $rules->check(postedit => $topic_name, $made_changes, $opt) and $made_changes) {
		Game::Plan::Revision->rollback;
		die "Bad edit; rolling back to previous commit.\n"
	}
}

$new_topic_contents = <<'NEW_TOPIC';
This file lets you write free text with tasks and rules sprinkled among the
prose. You should use the free text to clarify your thoughts and provide
context for your tasks and rules.

The examples that follow are "commented out". Real tasks and rules should
not begin with a hash mark.

To create a task that shows up when you say "gp list", say
# [ ] Cats - book vet

The square brackets are meant to evoke the notion of a check box. If you
fill the check box with a '+', or a '*', or almost anything else, it'll be
interpreted as completed and not included. However, you can also put a number
inside the square brackets to mean "Don't tell me about this for X days."
To skip a daily task for the next two weeks, use
# [14] Finances - check stocks @1
When the break has run its course, the topic file will be updated with an
empty pair of square brackets to indicate we're back on track.

Defaults are applied to any later task or rule whose description matches the
given pattern:
# /Morning - / Defaults { after => '5:00am', before => '8:00am' }
These values will be applied to your tasks and rules that do not provide
their own. These defaults only apply to tasks and rules that come after the
default has been declared.

Once you have completed this task, it will be checked off for you:
# [+] Cats - book vet

This will not have any points given to it (though completing it may lead to
points through rules that you define later). To assign a set of points, say
# [ ] Cats - book vet { 'points', 5 }
The list in curly brackets is inserted directly into the Task constructor,
so it can be any properly formatted Perl code. For example, because Perl is
an awesome language that provides succinct and readable syntactic shortcuts,
this version would also be acceptable:
# [ ] Cats - book vet { points => 5 }

There is special notation to indicate that certain tasks repeat weekly,
should occur on a specific date, or should have a regular recurrence. This
task shows up on Monday, Wednesday, and Friday:
# [ ] Teaching - prepare lectures @MWF
Thursday is abbreviated with an H, Saturday with an S, and Sunday with a U.
This task only shows up on November 2 of 2014:
# [ ] Teaching - think about next semester @2014/11/2 { points => 5 }
Digits followed by unit indicate repeat intervals. For example, suppose I
want to do something every other day:
# [ ] Home - check gutters @4days
This task will show up every four days. Notice that there is NO WHITE SPACE
between the number and the unit; also, decimal points are not allowed. The
date upon which it appears is relative to the most recent completion, so if
I complete this task on Sunday, it'll show up again on Thursday, Monday, etc.
If I complete it on Wednesday, even though it's not on my Wednesday list,
it'll show up again four days later, on Sunday. You can use other units, such
as weeks and months (and probably years), but bear in mind that the task will
Inly show up on your list for the repeat day. If you use longer units such as
weeks, or especially months, you should probably use the "~" marker, which I
discuss next.

Sometimes you want tasks to show up every day after a given refractory
period, and not give you peace until it's done. If I mow the lawn on
Saturday, I'd like to be reminded again the following Friday, on the
off-chance that I'll have time Friday afternoon:
# [ ] Home - mow lawn ~F
A better approach to checking my gutters (mentioned above) might be
# [ ] Home - check gutters ~4days
Just like with the "@" symbol, you can specify letters (week days), dates,
and relative durations (days, weeks, etc).

On a related note, you can put a task on hiatus for a specified number of
days. You do this by putting the number within the square brackets. This is
distinct from but functionally equivalent to "~Ndays", which means you can
combine it with other notations. For example, suppose I want a task to come
up every Friday, but if I completed it on Wednesday or Thursday, I wouldn't
want to be reminded again for a few days. By saying something like this:
# [4] Home - check gutters ~F
I essentially achieve that end.

Relative dates for "@" and "~" tasks are computed against the most recent
like-named task the Current task list. If there are none, a task of this
sort will show on C<gp list> immediately, and continue showing up
until you've completed it.

You can also restrict the time during the day when tasks show up:
# [ ] Home - cook dinner @MWUF { after => '5:00pm', before => '8:00pm' }
The arguments to "after" and "before" ought to be absolute times, not
relative. Bear in mind that this will restrict when the task gets shown by
gp list, so be sure to set the "after" argument early enough to serve as a
useful reminder before it actually needs to get done.

You can assign a numeric priority to a task, which you can use as a sort
criterion:
# [ ] Family - emergency { priority => 100 }
# [ ] Home - mow lawn ~F { priority => 30 }

# => Rule(description => 'Take out trash', points => 5)
# /trash/ => Rule(description => 'Take out trash', points => 5)
# [ ] => Rule(description => 'Take out trash', points => 5)
# [ ] /trash/ => Rule(description => 'Take out trash', points => 5)

NEW_TOPIC

$new_module_contents = <<'NEW_MODULE';
# This is a Perl module meant to be used by Topics. Consult the
# documentation for details on ow to add new rule classes and parsers.
use strict;
use warnings;

# Add a rule parser
# our @rule_parsers;
# push @rule_parsers, sub {
#     print "Parsing a line [$_]\n";
#     return '';  # return value is the class constructor string
# }

# Add a rule class
# package NewRule;
# our @ISA = qw(Rule);
# sub init {
#     my $self = shift;
#     croak('bad foo') unless exists $self->{foo};
# }
# sub check_start { ... }

1; # end with a true statement

NEW_MODULE

1;

__END__

=head1 NAME

App::gp::Command::new

Note: This will stop the previous activity if it is not planning related.

=head1 VALIDATION RULES

Rule sets that want to effect to new command can hook into the following
rules:

=over

=item new

Called before the user gets to edit the file. The argument to the new rule
is the topic file name. Failure of any rule will prevent the creation or
edit of the new topic or module.

=item edit

Called after the user has finished editing the file, and only if the file
was changed. This rule is called with the topic file name and the hash
containing the command-line options. Failure of any rule will prompt the
user to re-edit the file or discard any changes.

=item postedit

Called after the user performs the edits, possibly after having made none,
or having failed to make the desired changes due to parse or rule errors.
The arguments to the postedit rule are the topic file name, a boolean
indicating whether changes were actually made to the topic, and the hash
containing the command-line options. Failure of any rule will cause the
content of any edited files to be I<reverted to their content>, without the
option to re-edit. Therefore, only fail a postedit rule when a harsh
response is warranted.

=back

Rules can provide additional command-line keys. Applicable keys for this
command include B<new> and B<edit>. If the user's currently active task is
not a planning task (i.e. unless it starts with C<Plan - ...>), the current
task will also be stopped, and the command-line options for stopping are
also allowed.

=cut

