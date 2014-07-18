# ABSTRACT: Undo the most recent edit.
use strict;
use warnings;

############################################################################
                  package App::gp::Command::rollback;
############################################################################

use App::gp -command;
use Game::Plan::Revision;

sub description { '    Undoes the most recent edit.' }

sub execute {
	my ($self, $opt, $args) = @_;
#	die "Are you sure?";  # working here
	print "Undoing the most recent edit\n";
	Game::Plan::Revision->rollback;
}

1;

__END__

=head1 NAME

App::gp::Command::rollback

=head1 DESCRIPTION

This command undos the most recent edit. Of course, most edits can be
undone easily by re-editing the file, and this should be your usual approach
to revising your topics and modules.

The rare situation where you might use this command is when you accidentally
create a preedit or postedit rule that always fails. Either you won't be
allowed to make edits, or your edits will always be rejected. Your only
recorse is to either edit the file manually or undo the commit. This command
lets you painlessly undo the commit.

=cut