# ABSTRACT: List the available topics for planning
use strict;
use warnings;

############################################################################
                  package App::gp::Command::topics;
############################################################################

use App::gp -command;
use App::gp::Files;

sub execute {
	my ($self, $opt, $args) = @_;
	my @topics = App::gp::Files->topic_names;
	for my $topic (@topics) {
		print "  $topic\n";
	}
}

1;
