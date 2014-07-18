# ABSTRACT: Provide the path to the application's data directory
use strict;
use warnings;

############################################################################
                  package App::gp::Command::datapath;
############################################################################

use App::gp -command;
use App::gp::Files;

sub execute {
	my ($self, $opt, $args) = @_;
	print App::gp::Files->dir, "\n";
}

1;
