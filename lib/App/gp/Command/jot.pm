# ABSTRACT: Quickly record a task that needs doing
use strict;
use warnings;

############################################################################
                   package App::gp::Command::jot;
############################################################################

use App::gp -command;
use App::gp::Files;

sub usage_desc { '%c jot %o <description>' }

sub opt_spec {
	return (
		[ 'points=i', 'point-value for completing this task (default: 1)', {
			default => 1,
		}],
		[ 'chance=f', 'chance of getting the reward (default: 1)', {
			default => 1,
		}],
		[ 'topic=s', 'topic to which to add this jot (default: Jots)', {
			default => 'Jots',
		}],
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	my $description = $args->[0]
		or die "You must provide a new task description.\n";
	
	# Add this jot to the desired topic
	App::gp::Files::do_in_topics {
		# Get the topic file, make sure it's around
		my $topic_file = $opt->topic . '.topic';
		die "Topic file `$topic_file' does not exist\n"
			unless -f $topic_file;
		
		# Record the new task at the bottom of the file
		open my $out_fh, '>>', $topic_file;
		print $out_fh "Jot on " . localtime . "\n";
		print $out_fh " [ ] $description { points => $opt->{points}, chance => $opt->{chance}}\n";
		close $out_fh;
	};
	
	print "Jotted that down.\n";
}

1;

__END__

=head1 NAME

App::gp::Command::jot - quickly add tasks that need doing

=cut

