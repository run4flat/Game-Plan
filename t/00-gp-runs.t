use strict;
use warnings;

use Test::More;
use App::Cmd::Tester;

# Produce a temporary directory for testing
BEGIN {use File::Temp qw(tempdir) }
BEGIN {$ENV{PERL_GAME_PLAN_DATA_DIRECTORY} = tempdir( CLEANUP => 1 ) }

BEGIN { use_ok ('App::gp') }

# Does it run?
my $result = test_app('App::gp' => ['commands']);
is($result->exit_code, 0, 'App::gp runs successfully')
	or diag($result->output);

# Does it correctly state the datapath?
$result = test_app('App::gp' => ['datapath']);
is($result->exit_code, 0, 'App::gp can say datapath')
	or diag($result->output);
is($result->output, "$ENV{PERL_GAME_PLAN_DATA_DIRECTORY}\n",
	'App::gp respects PERL_GAME_PLAN_DATA_DIRECTORY');

done_testing;
