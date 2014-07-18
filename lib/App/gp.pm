use strict;
use warnings;


############################################################################
                           package App::gp;
############################################################################

use App::Cmd::Setup -app => {
	plugins => [ qw(Prompt) ],
};

use Game::Plan::CurrRules;
use Game::Plan::CurrTasks;
use Time::Piece;

# These are loaded and unloaded during the run command
my $tasks;
sub curr_tasks { $tasks ||= Game::Plan::CurrTasks->new }

my $rules = Game::Plan::CurrRules->new;
sub curr_rules { $rules }

# Overload this so that the reference handling works correctly
sub run {
	my ($self) = @_;
	
	$self = $self->new unless ref $self;
	
	# load the tasks
	$tasks ||= Game::Plan::CurrTasks->new;
	
	# Use App::Cmd's run command for the rest. The tasks are saved during
	# the object destroy, but some important ojbects are often destroyed
	# before the destructor gets called, so gaurd against failure here.
	eval { $self->SUPER::run };
	
	# Unload (save) the tasks
	undef ($tasks);
	
	# Rethrow any problems
	die($@) if ($@);
}

sub stopstatus_options {
	return [ stopstatus => hidden => {
		one_of => [
			[ 'finished|f', 'completed, award points' ],
			[ 'paused|p', 'temporarily' ],
			[ 'interupted|i', 'temporarily' ],
			[ 'canceled|c', 'not going to finish, award sympathy points' ],
			[ 'postponed|t', 'will resume on a future date' ],
		],
	}];
}

sub datetime_options {
	return [ 'at=s', 'specify the start/stop time (default: now)', {
		default => 'now',
	}];
}

1;
