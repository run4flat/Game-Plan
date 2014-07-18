# ABSTRACT: Estimate the chances of getting points and their likely values
use strict;
use warnings;

############################################################################
                  package App::gp::Command::estimate;
############################################################################

use App::gp -command;
use Game::Plan::CurrRules;

sub usage_desc { '%c estimate %o <task1> <task2> ...' }

my $description = 
'    Provides a set of point and chance estimates for the given tasks. This gives
you a good idea for how you are likely to be rewarded if you start the given
task right now. It combines the effect of each rule on the task, which is
especially useful when you have multiple complex rules that apply to a given
task.

The output is a table of the form

  task1
    min lq mean uq max   min lq mean uq max
  task2
    min lq mean uq max   min lq mean uq max
    
The first column gives information about the chance of getting points and
the second column gives information about the number of points that will be
awarded. The abbreviations mean:

  min  - minimum possible
  lq   - probably will not go lower than this
  mean - typical
  uq   - probably will not go higher than this
  max  = maximum possible

For example, I tend to spend too much time planning, so I have a complicated
reward structure for that task. On the other hand, feeding the cats is
something that I simply want done, and has a simple reward structure:

  $ gp estimate "Home - feed cats" "Plan - morning"
  Home - feed cats
    1.0  1.0  1.0  1.0  1.0       5     5     5     5     5
  Plan - morning
    0.0 0.75 0.85 0.95  1.0       0     8    12    14    15

This tells me that if I feed the cats, I will feed three points into the
poisson distribution that generates my final reward. If I choose to plan,
then there is some chance that I will get nothing (min chance is zero) but I
usually have an excellent shot at getting points. The points that go into
the Poisson distribution can range anywhere from zero to 15, but I can
expect to usually get above 10 points.';
$description =~ s/\n/\n    /g;
sub description { $description }

sub execute {
	my ($self, $opt, $args) = @_;
	my $rules = Game::Plan::CurrRules->new;
	$rules->print_estimates(@$args);
}

1;
