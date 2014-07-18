# ABSTRACT: List the available modules for planning
use strict;
use warnings;

############################################################################
                  package App::gp::Command::modules;
############################################################################

use App::gp -command;
use App::gp::Files;

sub description { '    Prints a list of currently available modules' }

sub execute {
	my ($self, $opt, $args) = @_;
	my @modules = App::gp::Files->module_names;
	for my $module (@modules) {
		print "  $module\n";
	}
}

1;
