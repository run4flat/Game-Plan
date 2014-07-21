=head1 NAME

Game::Plan::CurrRules - Apply the current rules

=head1 SYNOPSIS

 use Game::Plan::CurrRules;
 
 my $rules = Game::Plan::CurrRules->new;
 
 my $task = {
     description => 'foo - bar',
     start_time => {
         year => 2014,
         mon => 9,
         day => 13,
         hour => 14,
         min => 55,
         sec => 32
     },
 };
 
 print "Cannot start $task->{description}!\n"
     unless $rules->check(start => $task);
 
 $task->{stop_time} = {
     year => 2014,
     mon => 9,
     day => 13,
     hour => 15,
     min => 5,
     sec => 17,
 };
 
 print "Cannot stop $task->{description}!\n"
     unless $rules->check(stop => $task);

=cut

############################################################################
                      package Game::Plan::CurrRules;
############################################################################

use strict;
use warnings;
use App::gp::Files;
use Time::Piece;
use Game::Plan::Revision;
use Game::Plan::Timing;
use Math::Random qw(random_poisson);
use Safe::Isa;
use File::Slurp;

my @default_rule_parsers = (
	# Tasks
	sub {
		return unless /^(\s*)\[(\d+| |-)\]/;
		my $entry = $_;
		
		# Capture the bracket position if the bracket is empty.
		my $bracket_string = '';
		$bracket_string = 'bracket_offset => ' . (length($1) + 1) . ', '
			if $2 eq ' ';
		
		# Determine the skip from the bracket contents
		my $skip = $2;
		$skip = 0 unless $skip =~ /\d/;
		
		# Strip off the brackets
		$entry =~ s/^\s*\[[^\]]\]\s*//;
		
		# Pull off the command at the end
		my $args = '';
		$args = $1 if $entry =~ s/\{(.*)\}\s*$//;
		
		# Pull off the when
		my $when = '';
		$when = "when => '$1', " if $entry =~ s/([@~]\S+)\s*$//;
		
		# Strip trailing white space
		$entry =~ s/\s+$//;
		
		return "Game::Plan::Task->new(description => q{$entry}, "
			. $bracket_string . $when
			. "skip => $skip, defaults => \$defaults, $args)"
	},
	# Rules
	sub {
		if (/^\s*(\/.*?(?<!\\)\/\w*)\s+(\w+)\s*(\{(.*)\})?/) {
			my ($pattern, $class, $args) = ($1, $2, $4);
			$args ||= '';
			# Add the pattern argument
			$args = "pattern => qr$pattern, $args";
			# Return the constructor call
			return "Game::Plan::${class}->new(defaults => \$defaults, $args)";
		}
	},
);

sub new {
	# Load and parse the topic files
	my $self = bless { rules => [], defaults => [], tasks => [] };
	# Calculate this sha's package
	my $package = 'Game::Plan::Rules_' . Game::Plan::Revision::curr_hash;
	# Set up the defalt rules for this object/package
	{
		no strict 'refs';
		no warnings 'once';
		@{$package . '::rule_parsers'} = @default_rule_parsers;
	}
	# parse the topics
	$self->parse_topics($package);
	return $self;
}

sub cmd_line_options {
	my ($self, $command) = @_;
	my @options;
	for my $rule (@{$self->{rules}}) {
		push @options, $rule->cmd_line_options($command);
	}
	return @options;
}

sub parse_topics {
	my ($self, $package) = @_;
	App::gp::Files::do_in_topics {
		my @topics = sort glob('*.topic');
		$self->parse_topic($_, $package) foreach (@topics);
	};
}

# Rules based on patterns
#   /pattern/ RuleClass {arg1 => "foo", arg2 => "bar"}
# Rules must have a pattern, even if they are not based on patterns (i.e.
# time of invocation)
#   // RuleClass {arg1 => 'foo', arg2 => 'bar')

sub parse_topic {
	my ($self, $topic_file, $package) = @_;
	
	open my $in_fh, '<', $topic_file
		or die "Unable to open topic file $topic_file\n";
	
	# I need this common functionality, but I want to make sure that the
	# code has access to the different arrays. Thus, it is a lexical subref
	# rather than a normal function.
	my $defaults = $self->{defaults};
	my $tasks = $self->{tasks};
	my $rules = $self->{rules};
	my @things;
	my $do_parse_eval = sub {
		my $to_eval = shift;
		# Evaluate everything in the base package.
		eval "package $package;\n$to_eval";
		if ($@) {
			warn "Failed to parse rule in $topic_file on line $.: $@";
			return 1;
		}
		return 0;
	};
	
	#
	# Other code, including new rule classes, can be declared within lexical
	# blocks, delimited by an opening curly bracket, and closed with a
	# matching curly bracket either on the same line or on a later line with
	# the same indentation.
	
	my ($buffer, $indentation, $parse_failed);
	while (my $line = <$in_fh>) {
		# If we are currently accumulating a buffer...
		if ($buffer) {
			$buffer .= $line; # Add this line
			# see if we have found the end of the buffer
			if ($line =~ /^$indentation\}/) {
				$parse_failed += $do_parse_eval->($buffer);
				$buffer = undef;
			}
		}
		# Single-line code block
		elsif ($line =~ /^\s*\{.*\}\s*$/) {
			$parse_failed += $do_parse_eval->("#line $. $topic_file\n$line");
		}
		# Start of a code block
		elsif ($line =~ /^(\s+)\{/) {
			$indentation = $1;
			$buffer = "#line $. $topic_file\n$line";
		}
		# Invoke the rule parsers
		else {
			no strict 'refs';
			for my $parser (@{$package.'::rule_parsers'}) {
				use strict 'refs';
				local $_ = $line;
				if (my $to_eval = $parser->()) {
					@things = ();
					$parse_failed += $do_parse_eval->(
						"#line $. $topic_file\n\@things = do {$to_eval}");
					# Process our new things
					for my $thing (@things) {
						# Make sure it's derived from our base class
						next unless $thing->$_isa('Game::Plan::Rule');
						# Add the thing to the appropriate list
						if ($thing->isa('Game::Plan::Task')) {
							# If this is a mark-off-able task, store the
							# seek location:
							$thing->{bracket_offset}
								+= tell($in_fh) - length($line)
								if $thing->{bracket_offset};
							push @$tasks, $thing;
						}
						elsif ($thing->isa('Game::Plan::Defaults')) {
							push @$defaults, $thing;
						}
						else {
							push @$rules, $thing;
						}
					}
				}
			}
		}
	} # while(<$in_fh>)
	close $in_fh;
	die "Failed to parse topic $topic_file\n" if $parse_failed;
}

my @stop_options;

sub check {
	my ($self, $action, @args) = @_;
	
	if ($action eq 'stop') {
		# Add the stopstatus
		my ($task, $options) = @args;
		if (not exists $options->{stopstatus}) {
			print "Stopping: \"$task->{description}\"\n";
			# Base the options for the stop prompt on the list of stop reasons from
			# gp.pm.
			@stop_options = map { $_->[0] } @{(App::gp->stopstatus_options)[0][2]{one_of}}
				unless @stop_options;
			my $stop_reasons = join('|', map { substr($_,0,-2) } @stop_options);
			my $stop_letters = join('/', map { substr($_,-1,1)  } @stop_options);
			$stop_letters =~ s/i/I/;
			my $stop_regex = join('', map { substr($_,-1,1) } @stop_options);
			$stop_regex = qr/^[$stop_regex]$/i;
			my %letter_map = map { substr($_,-1,1) => substr($_,0,-2) } @stop_options;
			my $input = App::gp::Command::edittimesheet::prompt_str(
				"Why did you stop ($stop_reasons)?", {
				valid => sub { $_[0] =~ $stop_regex },
				default => 'i',
				choices => $stop_letters,
			});
			$task->{$letter_map{lc $input}} = 1;
		}
		else {
			$task->{$options->{stopstatus}} = 1;
		}
	}
	
	# Run the checks
	my $failed = 0;
	for my $rule (@{$self->{rules}}) {
		$failed++ unless $rule->check($action, @args);
	}
	return if $failed;
	return 1 if $action ne 'stop';
	return 1 unless $args[0]{finished} or $args[0]{canceled};
	
	# Score stopped tasks and return true. (The first argument to stop
	# action is the task hashref)
	$self->points($args[0]) if $action eq 'stop';
	return 1;
}

sub estimate {
	my ($self, $description) = @_;
	my %chance = map { +$_ => 1 } qw(min lower_quartile mean upper_quartile max);
	my %points = map { +$_ => 0 } qw(min lower_quartile mean upper_quartile max);
	return (\%chance, \%points) if not defined $description;
	
	for my $rule (@{$self->{tasks}}, @{$self->{rules}}) {
		next unless my ($chance, $points) = $rule->estimate($description);
		
		# Handle the chances
		if (not ref($chance)) {
			$_ *= $chance foreach (values %chance);
		}
		elsif (ref($chance) eq ref({})) {
			for my $k (keys %chance) {
				$chance{$k} *= $chance->{$k};
			}
		}
		# Handle the points
		if (not ref($points)) {
			$_ += $points foreach (values %points);
		}
		elsif (ref($points) eq ref({})) {
			for my $k (keys %points) {
				$points{$k} += $points->{$k};
			}
		}
	}
	
	return (\%chance, \%points);
}

sub print_estimates {
	my ($self, @descriptions) = @_;
	
	for my $description (@descriptions) {
		print "$description\n";
		my ($chance, $points) = $self->estimate($description);
		my %chance = %$chance;
		my %points = %$points;
		printf "  %2.1f  %2.1f  %2.1f  %2.1f  %2.1f   %4d  %4d  %4d  %4d  %4d\n",
			@chance{ qw(min lower_quartile mean upper_quartile max) },
			@points{ qw(min lower_quartile mean upper_quartile max) };
	}
}

# Computes the points total and chance for a task; meant to be used to
# give a status for the current task, and to serve as the basis for the
# final points allocation as given below.
sub point_status {
	my ($self, $task) = @_;
	
	# Accumulate the chance and point contribution from each rule
	my ($chance, $points) = (1, 0);
	for my $rule (@{$self->{tasks}}, @{$self->{rules}}) {
		next unless my ($dchance, $dpoints, $rule_description)
			= $rule->points($task);
		$chance *= $dchance;
		$points += $dpoints;
		printf "  *%1.2f, +%-4d: $rule_description\n", $dchance, $dpoints;
	}
	return ($chance, $points);
}

# Computes the points awarded for a task
sub points {
	my ($self, $task) = @_;
	
	# If the points have already been computed, use them
	return $task->{points} if exists $task->{points};
	
	# Get the current chance and points
	my ($chance, $points) = $self->point_status($task);
	
	# Calculate points according to the poisson distribution for the given
	# points, if the user is lucky enough to get them.
	$task->{points} = 0;
	$task->{points} = random_poisson(1, $points) if $chance > rand;
	print "          $task->{points} points\n";
	return $task->{points};
}

# Options: time, topics, pattern, priority_range, sort_by, point_range
sub get_list {
	my $self = shift;
	croak('get_list expects a set of key/value pairs')
		unless @_ % 2 == 0;
	my %opts = @_;
	
	# Validate inputs: priority range (two-element array),
	# point range (two-element array), topics (scalar|array),
	# pattern (regex), at (time string)
	for my $arg (qw(priority_range point_range)) {
		if ($opts{$arg}) {
			croak("$arg must be a two-element arrayref")
				unless ref($opts{$arg})
					and ref($opts{$arg}) eq ref([])
					and @{$opts{$arg}} == 2;
			# Copy the range so we can modify it
			my $r = $opts{$arg} = [@{$opts{$arg}}];
			$r->[0] ||= 0;
			$r->[1] ||= 1e10;
			croak("$arg expects positive numbers or undef")
				if not looks_like_number($r->[0])
					or not looks_like_number($r->[1]);
		}
	}
	if ($opts{topics}) {
		if (not ref($opts{topics})) {
			$opts{topics} = [$opts{topics}];
		}
		elsif (ref($opts{topics}) ne ref([])) {
			croak('topics must be an arrayref of topic names');
		}
		# Append the .topic file extension
		$opts{topics} = [
			map { $_ .= '.topic' unless /\.topic$/; $_ } @{$opts{topics}}
		];
	}
	croak('pattern must be a regex reference')
		if $opts{pattern} and ref($opts{pattern}) ne ref(qr//);
	if ($opts{at}) {
		$opts{at} = Game::Plan::Timing::get_datetime($opts{at});
	}
	else {
		$opts{at} = localtime;
	}
	
	# Filter out the rules that do not claim to match
	my @matches = grep { $_->get_list(%opts) } @{$self->{tasks}};
	
	# Exclude today unless it is explicitly mentioned
	if (not grep /^Today.topic$/, @{$opts{topics}}) {
		@matches = grep { $_->{file} ne 'Today.topic' } @matches;
	}
	
	# Tabulate the potential points
	my %points_for;
	for my $task (@matches) {
		my $d = $task->{description};
		my ($chance, $points) = $self->estimate($d);
		$points_for{$d} = $points->{mean};
	}
	# Filter out by points
	if ($opts{point_range}) {
		my @r = @{$opts{point_range}};
		@matches
			= grep { $r[0] <= $points_for{$_} and $points_for{$_} <= $r[1] }
				@matches;
	}
	
	# Sort
	if ($opts{by} and $opts{by} ne 'default') {
		my $sort_sub;
		if ($opts{by} eq 'alpha') {
			$sort_sub = sub { $a->{description} cmp $b->{description} };
		}
		# points, priority
		elsif ($opts{by} eq 'points') {
			$sort_sub = sub {
				$points_for{$a->{description}} <=> $points_for{$b->{description}}
			};
		}
		elsif ($opts{by} eq 'priority') {
			$sort_sub = sub { ($a->{priority} || 0) cmp ($b->{priority} || 0) };
		}
		@matches = sort $sort_sub @matches;
	}
	
	# Cache the list of tasks
	App::gp::Files::do_in_data {
		write_file('list-cache', map { $_->description . "\n" } @matches);
	};
	
	# Return our results
	return \@matches, \%points_for;
}

sub mark_as_completed {
	my ($self, $task, $mark) = @_;
	
	# Run through all the tasks and mark any that match
	for my $task_rule (@{$self->{tasks}}) {
		$task_rule->mark_as_completed($task, $mark)
			if $task_rule->matches($task->{description});
	}
}

############################################################################
                       package Game::Plan::Rule;
############################################################################

use Carp;
use v5.10;
use Scalar::Util qw(blessed looks_like_number);

sub new {
	my $class = shift;
	croak("New $class expects key/value pairs") if @_ % 2 == 1;
	
	# Get the line and file in which this rule is declared
	my ($package, $filename, $line) = caller;
	
	# Build self. Chance is multiplicative, points is additive
	my $self = bless {
		file => $filename, line => $line, chance => 1, points => 0,
		@_
	}, $class;
	
	# Apply defaults
	if (my $defaults = delete $self->{defaults}) {
		for my $default (@$defaults) {
			$default->apply_defaults($self);
		}
	}
	
	# Initialization
	$self->init;
	
	return $self;
}

# Check the description and probabilities
sub init {
	my $self = shift;
	$self->die('description must be a scalar')
		if exists $self->{description} and ref($self->{description});
	$self->die('chance must be a number')
		unless looks_like_number($self->{chance});
	$self->die('points must be a number')
		unless looks_like_number($self->{points});
	$self->{pattern} ||= qr/^$self->{description}$/;
}

sub description  {
	my $self = shift;
	return $self->{description} || $self->{pattern} || '(No description)';
}
sub matches {
	my ($self, $description) = @_;
	return if not defined $description;
	return $description =~ $self->{pattern};
}

# Calculate the chance and points for the current task. 
sub points {
	my ($self, $task) = @_;
	return unless $self->matches($task->{description});
	return ( $self->{chance}, $self->{points}, $self->description );
}

# Estimate the range of points and likelihoods for a task if it were to
# start now. The logic for this is nearly identical to the points function
# above, but it expects a description, not a task. Also, the job of this
# function is to return the potential range of values if applicable; simple
# rules do not have ranges, but derived classes may override both the points
# and estimate rules to implement variable ranges.
sub estimate {
	my ($self, $description) = @_;
	return ( $self->{chance}, $self->{points} )
		if $self->matches($description);
	return;
}

sub check {
	my $self = shift;
	my $action = shift;
	
	# Delegate based on various possibilities. First priority goes to check
	# methods
	my $method = $self->can("check_$action");
	return $self->$method(@_) if $method;
	if (exists $self->{$action}) {
		if (not ref ($self->{$action})) {
			# Scalar. Assume this is a message to print
			say $self->{$action};
			return 1;
		}
		# Subref. Assume it is a coderef
		return $self->{$action}->($self, @_) if ref($self->{$action}) eq ref(sub{});
		# Delegate to object
		return $self->{$action}->check($self, $action, @_)
			if blessed($self->{$action}) and $self->{$action}->can('check');
		# Issue warning
		my $action_type = ref($self->{$action});
		$self->warn("Unable to delegate action `$action' to type $action_type");
	}
	return 1;
}

sub get_list {}

sub cmd_line_options {}

sub mark_as_completed {}

sub warn {
	my ($self, @message) = @_;
	@message = ($@) unless @message;
	chomp(my $to_say = join('', @message));
	my $class = blessed($self);
	$class =~ s/^Game::Plan:://;
	warn "$to_say for rule $class declared in $self->{file} on line $self->{line}\n";
}

sub die {
	my ($self, @message) = @_;
	@message = ($@) unless @message;
	chomp(my $to_say = join('', @message));
	my $class = blessed($self);
	$class =~ s/^Game::Plan:://;
	die "$to_say for rule $class declared in $self->{file} on line $self->{line}\n";
}

############################################################################
                       package Game::Plan::Defaults;
############################################################################

our @ISA = qw(Game::Plan::Rule);

sub apply_defaults {
	my ($self, $new_rule) = @_;
	# Only apply if we match the *description*, not the cobbled description
	# that might be based on a pattern. The latter can self-match. D-:
	return unless $self->matches($new_rule->{description} || '');
	
	# Run through all of the keys and assign them if they do not exist
	# in the new rule (with the following handful of exceptions)
	my %ignore = map { +$_ => 1 } qw (description pattern file line );
	KEY: for my $k (keys %$self) {
		next KEY if $ignore{$k};
		$new_rule->{$k} = $self->{$k} unless exists $new_rule->{$k};
	}
}

############################################################################
                         package Game::Plan::Task;
############################################################################

our @ISA = qw(Game::Plan::Rule);
use Time::Piece;
use Time::ParseDate;
use Scalar::Util qw(looks_like_number);
use Time::Seconds;

sub init {
	my $self = shift;
	$self->{list_checks} = sub { return $self };
	
	# Find the most recent copy of this task in the backlog, if we need to
	# know that.
	my ($most_recent, $most_recent_postponed) = App::gp->curr_tasks->find($self->{description});
	if ($most_recent) {
		$self->{most_recent_match} = $most_recent;
		my $start = $most_recent->{start_time};
		$self->{most_recent_day}
			= $start - $start->sec - ONE_MINUTE * $start->min
				- ONE_HOUR * $start->hour;
	}
	if ($most_recent_postponed) {
		my $post_day = $most_recent_postponed->{start_time};
		$post_day -= $post_day->sec + ONE_MINUTE * $post_day->min
			+ ONE_HOUR * $post_day->hour;
		
		# Add a list check for most recent postpone
		my $curr_subref = $self->{list_checks};
		$self->{list_checks} = sub {
			my ($time, $day) = @_;
			return if $day == $post_day;
			return $curr_subref->($time, $day);
		};
	}
	
	# Skip should just be digits
	if ($self->{skip}) {
		$self->die('Skip must be just digits') if $self->{skip} !~ /^\d+$/;
		# We don't need to add a check if there is not recent task
		if (my $most_recent_day = $self->{most_recent_day}) {
			my $skip_sec = ONE_DAY * $self->{skip};
			my $curr_subref = $self->{list_checks};
			$self->{list_checks} = sub {
				my ($time, $day) = @_;
				return if $time < $most_recent_day + $skip_sec;
				return $curr_subref->($time, $day);
			};
		}
	}
	
	# Handle the many ways to say "when"
	$self->parse_when;
	
	# priority
	$self->{priority} ||= 0;
	$self->{priority} =~ /^\d+$/ or die "Prioirity must be a positive integer\n";
	
	# after
	if (my $after = $self->{after}) {
		# Make sure the after string parses
		eval {
			Game::Plan::Timing::get_datetime($after);
			1;
		} or $self->die;
		# Add a check subref
		my $curr_subref = $self->{list_checks};
		$self->{list_checks} = sub {
			my ($time, $day) = @_;
			return if $time < parsedate($after, $time);
			return $curr_subref->($time, $day);
		};
	}
	# before
	if (my $before = $self->{before}) {
		# make sure the before string parses
		eval {
			Game::Plan::Timing::get_datetime($before);
			1;
		} or $self->die;
		# Add a check subref
		my $curr_subref = $self->{list_checks};
		$self->{list_checks} = sub {
			my ($time, $day) = @_;
			return if $time > parsedate($before, $time);
			return $curr_subref->($time, $day);
		};
	}
}

sub parse_when {
	my $self = shift;
	my $curr_subref = $self->{list_checks};
	my $most_recent_day = $self->{most_recent_day};
	
	my $w = $self->{when};
	return unless $w;
	
	# Note: if we couldn't find most recent day, then we impose no
	# limitations
	if ($w =~ s/^@//) {
		if ($w =~ /^\d+$/) {
			# repeat every N days; skip if we aren't on one of those days
			my $every_day_in_sec = $w * ONE_DAY;
			$self->{list_checks} = sub {
				my ($time, $day) = @_;
				return if ($day - $most_recent_day) % $every_day_in_sec != 0;
				return $curr_subref->($time, $day);
			} if defined $most_recent_day;
		}
		elsif ($w =~ /^[MTWHFSU]+$/) {
			# List on the given day of the week; skip if we aren't on one of
			# those days
			my $every_week = $w;
			$self->{list_checks} = sub {
				my ($time, $day) = @_;
				return if $every_week and -1 == index($every_week,
						Game::Plan::Timing::letter_from_day($time));
				return $curr_subref->($time, $day);
			};
		}
		else {
			# List on a given date. Make sure that the date parses, then add
			# a simple comparison check.
			my $every_date = eval { Game::Plan::Timing::get_datetime($w) }
				or $self->die;
			$self->{list_checks} = sub {
				my ($time, $day) = @_;
				return if $day != $every_date;
				return $curr_subref->($time, $day);
			};
		}
	}
	elsif ((my $w = $self->{when}) =~ s/^~//) {
		if ($w =~ /^\d+$/) {
			# Skip if we're still in the refractory period
			my $refractory_period = $w * ONE_DAY;
			$self->{list_checks} = sub {
				my ($time, $day) = @_;
				return if $time < $most_recent_day + $refractory_period;
				return $curr_subref->($time, $day);
			} if defined $most_recent_day;
		}
		elsif ($w =~ /^[MTWHFSU]+$/) {
			# Only list after a given weekday has passed since the last time
			# we finished. Skip if none of those days have passed.
			my $week_days = $w;
			
			$self->{list_checks} = sub {
				my ($time, $day) = @_;
				my $test_day = $most_recent_day;
				# Check the letter for each day since the most recent. If any
				# day validates, continue with any remaining validation subs.
				while($test_day <= $day) {
					return $curr_subref->($time, $day)
						if index($week_days, Game::Plan::Timing::letter_from_day($test_day)) > -1;
					$test_day = $test_day + ONE_DAY;
				}
				# Day hasn't passed, so this shouldn't be listed
				return;
			} if defined $most_recent_day;
		}
		else {
			my $next_date = eval { Game::Plan::Timing::get_datetime($w) }
				or $self->die;
			$self->{list_checks} = sub {
				my ($time, $day) = @_;
				return if $time < $next_date;
				return $curr_subref->($time, $day);
			};
		}
	}
	else { die "How did you get here?" }
}

# Complex listing functionality, as well as points and scoring
sub get_list {
	my ($self, %opt) = @_;
	
	# We only list tasks/rules with descriptions
	return if not exists $self->{description};
	
	# Check if it should display, based on the many conditions that might be
	# specified, including Topic, regex, before/after. Also include whether
	# this task should be listed based on its own listing criterea (i.e.
	# after and next conditions). Relative times should be taken with
	# respect to the given time:
	my $time = $opt{at};
	my $day = $time - $time->sec - ONE_MINUTE * $time->min
		- ONE_HOUR * $time->hour;
	
	# Skip if the specified topic does not match our source(s)
	return if $opt{topics} and 0 == grep { $self->{file} eq $_ } @{$opt{topics}};
	
	# Skip if the specified pattern does not match our description
	return if $opt{pattern} and $self->{description} !~ $opt{pattern};
	
	# Skip if we don't fall into the given priority range
	if ($opt{priority_range}) {
		return unless my $p = $self->{priority};
		my @range = @{$opt{priority_range}};
		return if $p < $range[0] or $range[1] < $p;
	}
	
	# Note: point range specs require applying the different rules to the
	# various tasks; I will leave that to the caller of this check_list to
	# figure out.
	
	# Apply the remaining list of checks. If any of these fail, they will
	# return undef. If they all succeed, they will return self.
	return $self->{list_checks}->($time, $day);
}

sub matches {
	my ($self, $description) = @_;
	return if not defined $description;
	return $self->{description} eq $description;
}

sub mark_as_completed {
	my ($self, $task, $mark) = @_;
	
	return unless $self->{bracket_offset};
	
	# Make changes to the topics that get recorded
	Game::Plan::Revision::do_and_commit {
		open my $fh, '+<', $self->{file} or do {
			warn "Unable to mark task in $self->{file} as completed\n";
			return;
		};
		sysseek $fh, $self->{bracket_offset}, 0;
		syswrite $fh, $mark, 1;
		close $fh;
	};
}

############################################################################
                      package Game::Plan::TimePoints;
############################################################################

our @ISA = qw(Game::Plan::Rule);
use Time::Piece;
use Time::ParseDate;

# Helps create rules that only apply during certain times of day
# from => '8:30am', until => '12:30pm', limit => 30, points_per_min => 3

use Scalar::Util qw(looks_like_number);
sub init {
	my $self = shift;
	
	# Handle the from and until arguments. Convert to seconds after midnight
	$self->{from}  ||= '0:00';
	$self->{until} ||= '23:59:59';
	for my $arg (qw(from until)) {
		eval {
			$self->{$arg} = Game::Plan::Timing::get_datetime($self->{$arg});
			1;
		} or $self->die;
	}
	
	# Make sure we have a valid limit
	$self->{limit} ||= '1 day';
	eval {
		parsedate($self->{limit});
		1;
	} or $self->die;
	
	# Make sure the points per minute are valid
	$self->{points_per_minute} ||= 1;
	$self->die('points per minute must be a number')
		unless looks_like_number($self->{points_per_minute});
}

sub estimate {
	my ($self, $description) = @_;
	
	# Check the description regex
	return unless $self->matches($description);
	
	# Check the time restriction
	my $time = localtime;
	return if $time < $self->{from} or $time > $self->{until};
	
	# Calculate the maximum possible seconds, and then points
	my $limit_seconds = parsedate($self->{limit}, NOW => $time) - $time;
	my $range_seconds = $self->{until} - $self->{from};
	my $max_seconds = $range_seconds;
	$max_seconds = $limit_seconds if $limit_seconds < $max_seconds;
	my $max = int($max_seconds * $self->{points_per_minute} / 60);
	
	return (1,
	{
		min => 0, max => $max, mean => int($max/2),
		lower_quartile => int($max/4), upper_quartile => int(3*$max/4)
	});
}

sub points {
	my ($self, $task) = @_;
	
	# Check the description regex
	return unless $self->matches($task->{description});
	
	# Make sure we don't apply if we're not supposed to (i.e. if another
	# rule set the no_timepoints flag already).
	return if $task->{no_timepoints};
	
	my $stop_time = $task->{stop_time};
	my $start_time = $task->{start_time};
	
	# Check the time restriction by comparing the number of seconds since
	# midnight.
	return if $self->{until} < $start_time or $stop_time < $self->{from};
	
	# Limit start and stop seconds by our rule's limits
	$start_time = $self->{from}  if $start_time < $self->{from};
	$stop_time  = $self->{until} if $stop_time  > $self->{until};
	
	# Looks like we're giving points. Calculate the points, linear in the
	# number of minutes.
	my $seconds = $stop_time - $start_time;
	my $limit_sec = parsedate($self->{limit}, $task->{start_time});
	$seconds = $limit_sec if $seconds > $limit_sec;
	my $points = int($seconds * $self->{points_per_minute} / 60);
	
	return (1, $points, $self->description);
}

############################################################################
                      package Game::Plan::ChanceDecay;
############################################################################

=head2 ChanceDecay

The likelihood of getting points either decays with time after a certain
point or exponentially grows with time up to a certain point.

If I begin a decay after a certain time, it provides a very strong incentive
to finish at or before the decay sets in. If I provide exponential growth
up to a certain time, it provides a very strong incentive to work on a task
for at least a given duration.

=cut

our @ISA = qw(Game::Plan::Rule);
use Time::Piece;

# after => '30 min', half_life => '15 min'
# after => '10:00pm', half_life => '30 min'
# before => '9:00am', half_life => '60 min'

use Scalar::Util qw(looks_like_number);
sub init {
	my $self = shift;
	
	# Must give either before or after
	$self->die('Must specify before or after')
		if not exists $self->{before} and not exists $self->{after}
			or exists $self->{before} and exists $self->{after};
	# Half life must exist
	$self->die('Must specify a half_life') if not exists $self->{half_life};
	
	# Make sure that all potential times parse correctly
	for my $arg (qw(before after)) {
		next if not exists $self->{$arg};
		
		eval {
			Game::Plan::Timing::get_datetime($self->{$arg});
			1;
		} or $self->die("Bad `$arg' time spec `", $self->{$arg}, '"');
	}
	
	# Make sure the half life is a future time
	my $half_life = Game::Plan::Timing::get_datetime($self->{half_life});
	$self->die('half_life must be a positive number')
		if $half_life <= localtime;
	
	# time constant in terms of half-life:
	# exp(-$hl/$tau) = 0.5;
	# $hl = -log(0.5) * $tau
	# $tau = -$hl / log(0.5);
	$self->{time_constant} = ($half_life - localtime) / log(0.5);
}

sub estimate {
	my ($self, $description) = @_;
	
	# Check the description regex
	return unless $self->matches($description);
	
	my $time = localtime;
	
	# Tweak the expected min and max based on the before or after time. The
	# min and max values can only be constrained under specific circumstances.
	my ($min, $max) = (0, 1);
	
	if ($self->{before}) {
		my $before_time = Game::Plan::Timing::get_datetime($self->{before});
		return (1, 0) if $time > $before_time;
		my $time_to_full_height = $before_time - $time;
		$min = exp(-$time_to_full_height / $self->{time_constant});
	}
	elsif ($self->{after}) {
		my $after_time = Game::Plan::Timing::get_datetime($self->{after});
		$max = exp(-($time - $after_time) / $self->{time_constant})
			if $time > $after_time;
	}
	
	my $range = $max - $min;
	return (
		{
			min => $min, max => $max, mean => 0.7 * $range + $min,
			lower_quartile => 0.3 * $range + $min,
			upper_quartile => 0.85 * $range + $min,
		},
		1
	);
}

sub points {
	my ($self, $task) = @_;
	
	# Check the description regex
	return unless $self->matches($task->{description});
	
	# Make sure we don't apply if we're not supposed to (i.e. if another
	# rule set the no_chancedecay flag already).
	return if $task->{no_chancedecay};
	
	my $seconds;
	if ($self->{after}) {
		my $after_time = Game::Plan::Timing::get_datetime($self->{after},
			$task->{start_time});
		$seconds = $task->{stop_time} - $after_time;
	}
	else {
		my $before_time = Game::Plan::Timing::get_datetime($self->{before},
			$task->{start_time});
		$seconds = $before_time - $task->{start_time};
	}
	$seconds = 0 if $seconds < 0;
		
	return (exp(-$seconds / $self->{time_constant}), 0, $self->description);
}

1;
