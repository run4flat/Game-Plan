# ABSTRACT: List, filter, and sort tasks that need doing
use strict;
use warnings;

############################################################################
                  package App::gp::Command::list;
############################################################################

use App::gp -command;
use App::gp::Files;
use File::Slurp;

sub description { '    List, filter, and sort tasks that need doing' }

sub opt_spec {
	return (
		['append=s', 'append the resulting task list to the given topic file'],
		['by=s', 'sort order, one of points, priority, alpha, default'],
		['pattern|p=s', 'pattern to match against the description'],
		['point_range=s', 'limit tasks to fall within the point range (numbers separated by dashes)'],
		['priority_range=s', 'limit tasks to fall within the priority range (numbers separated by dashes)'],
		['recent|r:i', 'list recently completed tasks (other options ignored)'],
		['today|t', 'list tasks from today'],
		['topics=s', 'only show tasks from the given topics'],
	);
}

sub execute {
	my ($self, $opt, $args) = @_;
	
	my @task_descriptions;
	if (defined (my $N_to_list = $opt->recent)) {
		$N_to_list ||= 5;
		my $tasks = App::gp->curr_tasks;
		
		# list recent tasks
		my @tasks;
		for (my $i = 0; $i < $N_to_list; $i++) {
			last unless $tasks->[$i];
			push @tasks, $tasks->[$i]{description};
			printf "  %2d: $tasks->[$i]{description}\n", $i+1;
		}
		print "  ... more details to come... some day...\n";
		
		# Cache the list of tasks
		App::gp::Files::do_in_data {
			write_file('list-cache', map { "$_\n" } @tasks);
		};
		@task_descriptions = @tasks;
	}
	else {
		
		# Touch up the options hash
		my %options;
		if (my $p = $opt->pattern) {
			$options{pattern} = qr/$p/;
		}
		$options{topics} = [split /,/, $opt->topics] if $opt->topics;
		$options{point_range} = [split /,/, $opt->point_range]
			if $opt->point_range;
		$options{priority_range} = [split /,/, $opt->priority_range]
			if $opt->priority_range;
		
		# Work with the Today topic if the -t flag was invoked and said topic
		# exists.
		App::gp::Files::do_in_topics {
			$options{topics} = ['Today'] if $opt->today and -f 'Today.topic';
		};
		
		# Get the list of matching tasks
		my ($task_rules, $points) = App::gp::curr_rules->get_list(%options);
		@task_descriptions = map { $_->description } @$task_rules;
		
		# print them, along with their points
		my $i = 0;
		for my $task (@$task_rules) {
			$i++;
			my $d = $task->description;
			printf "  %2d: $d (%d points)\n", $i, $points->{$d};
		}
	}
	
	if ($opt->append) {
		Game::Plan::Revision::do_and_commit {
			my $topic_file = $opt->append;
			$topic_file .= '.topic' unless $topic_file =~ /\.topic$/;
			die "Topic file $topic_file not found\n"
				unless -f $topic_file;
			open my $out_fh, '>>', $topic_file
				or die "Unable to open $topic_file for append\n";
			for my $d (@task_descriptions) {
				print $out_fh "[ ] $d\n";
			}
			close $out_fh;
			print "Appended tasks to $topic_file\n";
			return 1;
		};
	}
}

1;
