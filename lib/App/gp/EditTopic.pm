=head1 NAME

App::gp::EditTopic - editing a topic, with version control

=head1 SYNOPSIS

 use App::gp::EditTopic;
 
 App::gp::EditTopic::edit('TheTopic.topic');
 # When the function returns, the topic's changes
 # will already be checked in to the git repo!

=cut

############################################################################
                      package App::gp::EditTopic;
############################################################################

use strict;
use warnings;
use App::gp::Files;

sub edit {
	my ($topic_file, $opt) = @_;
	my $made_changes = 0;
	App::gp::Files::do_in_topics {
		my $amend = 0;
		while(1) {
			my $edit_cmd = $ENV{EDITOR} || 'nano';
			system($edit_cmd, $topic_file);
			
			# Done if they didn't make any changes
			$made_changes = Game::Plan::Revision->commit($amend);
			return unless $made_changes;
			
			# All commits after the first should amend to the first:
			$amend = 1;
		
			# If changes, we're done as long as they parse and pass edit rules
			my $passes_edit_checks
				= App::gp->curr_rules->check(edit => $topic_file, $opt);
			print "Edits do not pass.\n" unless $passes_edit_checks;
			if (eval { Game::Plan::CurrRules->new }) {
				return if $passes_edit_checks;
			}
			else {
				# Failed to parse
				print "Edits have an error: $@";
			}
			
			# ask if they want to re-edit
			my $input = App::gp::Command::edittimesheet::prompt_str('Edit again or discard changes?', {
				valid => sub { $_[0] =~ /^[ex]$/i },
				default => 'e',
				choices => 'E/x',
			});
			
			# Roll back if they want to exit
			if ($input eq 'x') {
				Game::Plan::Revision->rollback;
				$made_changes = 0;
				return;
			}
		}
	};
	return $made_changes;
}

1; # all done
