=head1 NAME

App::gp::Files - functions to retrieve files used by C<gp>.

=head1 SYNOPSIS

 use App::gp::Files;
 
 print "The current timesheet file is ", App::gp::Files->ts, "\n";
 print "Timesheet archive is ", App::gp::Files->ts_archive, "\n";
 
 print "Topics are ",
     join(', ', App::gp::Files->topic_namess), "\n";
 # Similar for modules
 
 App::gp::Files::do_in_topics {
     # When this code is executed, the program
     # will be in the program's directory.
     print "All project files are ", join(', ', glob('*')), "\n";
 };

=head1 DATA DIRECTORY

The default data directory is the L<dist directory|File::HomeDir/my_dist_data>
returned by L<File::HomeDir>. You can override this directory by setting the
C<PERL_GAME_PLAN_DATA_DIRECTORY> environment variable to any acceptable (i.e.
existing) path. This was originally added to facilitate testing. I commonly
override this to point to a path that is synced on the cloud, so that my
plans are synchronized across multiple devices automatically.

=cut

############################################################################
                       package App::gp::Files;
############################################################################

use strict;
use warnings;
use File::HomeDir;
use File::Spec;
use File::chdir;

# Allow override of planning directory via an environment variable, so that
# I can easily test the system.
my $dir = $ENV{PERL_GAME_PLAN_DATA_DIRECTORY}
	|| File::HomeDir->my_dist_data('App-gp', { create => 1});
die "Data directory `$dir' does not exist!\n" unless -d $dir;

my $topics_dir = File::Spec->catdir($dir, 'planning');
mkdir $topics_dir unless -d $topics_dir;

sub dir { $dir }

sub do_in_data (&) {
	my $subref = shift;
	local $CWD = $dir;
	$subref->();
}

sub ts {
	File::Spec->catfile($dir, 'timesheet.json');
}

sub ts_archive {
	File::Spec->catfile($dir, 'archive.json');
}

sub do_in_topics (&) {
	my $subref = shift;
	local $CWD = $topics_dir;
	$subref->();
}

sub topic_names {
	my @topics;
	do_in_topics {
		@topics = map { s/\.topic$//; $_ } glob('*.topic');
	};
	return @topics;
}

sub module_names {
	my @modules;
	do_in_topics {
		@modules = glob('*.pm');
	};
	return @modules;
}

1; # all done
