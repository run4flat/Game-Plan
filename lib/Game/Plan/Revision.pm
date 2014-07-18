=head1 NAME

Game::Plan::Revision - track revisions, rewind to previous states

=head1 SYNOPSIS

 use App::gp;
 use Game::Plan::Revision;
 
 Game::Plan::Revision::do_and_commit {
    system('nano', $filename);
    return 0 if $failed;
    ...
    return 1;
 };
 
 Game::Plan::Revision::rewind_and_do $timestampe => sub {
     # execute some code, but don't change anything!!
 };

=cut

############################################################################
                      package Game::Plan::Revision;
############################################################################

use strict;
use warnings;
use App::gp::Files;
use File::Spec;

sub ensure_git {
	# Make sure we have version control in place
	local $? = 0;
	`git init --quiet` unless -d '.git';
	die "Unable to initialize version control!\n" if $? != 0;
}

sub ensure_master {
	ensure_git;
	return 1 if glob File::Spec->catfile(qw( .git refs heads * ));
}

#sub ensure_previous {
#	return unless ensure_master;
#	my
#}

sub is_dirty {
	# Get the git status of the current working directory
	return !!`git diff --shortstat` || !!`git diff --shortstat --cached`;
}

# Adds the latest file edits and commits them.
sub commit {
	my ($class, $amend) = @_;
	if ($amend) {
		$amend = '--amend';
	}
	else {
		$amend = '';
	}
	my $found_change;
	App::gp::Files::do_in_topics {
		ensure_git;
		`git add *`;
		if (is_dirty) {
			`git commit --quiet $amend -am.`;
			$found_change = 1;
		}
	};
	return $found_change;
}

# Reverts master to the previous commit. Useful if a just-performed commit
# is actually a bad idea.
use File::Path qw(remove_tree);
sub rollback {
	App::gp::Files::do_in_topics {
		# Nothing committed yet
		if (not ensure_master) {
			unlink $_ foreach (glob '*');
			return;
		}
		# Check for more than one commit
		if (`git log -1 --skip=1`) {
			`git reset --quiet --hard HEAD~1`;
			return;
		}
		# Only a single commit. Remove it, and the git repo, since there's
		# no way to tell git to start over apart from removing it.
		unlink $_ foreach (glob '*');
		remove_tree('.git');
	};
}

sub do_and_commit (&) {
	my $subref = shift;
	App::gp::Files::do_in_topics {
		ensure_git;
		
		# Execute the code. If this returns true, then add all the files
		# and commit. Otherwise, roll back to the previous commit.
		my $success = $subref->();
		if ($success) {
			`git add *`;
			if (is_dirty) {
				`git commit --quiet -am.`;
			}
			else {
				print "Nothing to commit\n";
			}
		}
		else {
			`git reset --quiet --hard HEAD`;
		}
	};
}

sub rewind_and_do {
	my ($timestamp, $subref) = @_;
	App::gp::Files::do_in_topics {
		ensure_git;
		
		# Get the first commit before the given timestamp
		my $commit = `git log -1 --date=raw --pretty=format:%H --before=$timestamp`
			if `git branch`; # edge condition: no commits yet
		
		if ($commit) {
			`git checkout --quiet $commit`;
			my $success = $subref->();
			
			# Ensure we have a clean state
			if (not $success) {
				`git reset --quiet --hard HEAD`;
			}
			elsif (is_dirty) {
				print "Losing all changes!\n";
				`git reset --quiet --hard HEAD`;
			}
			
			`git checkout --quiet master`;	
		}
		else {
			print "No commit before timestamp ($timestamp)\n";
		}
	};
}

sub curr_hash {
	my $to_return;
	App::gp::Files::do_in_topics {
		ensure_git;
		# If no check-ins, then return a string to indicate that
		return $to_return = 'init' unless `git branch`;
		# Otherwise, get the hash from the git log
		chomp($to_return = `git log -1 --pretty=format:%H`);
	};
	return $to_return;
}

1;

