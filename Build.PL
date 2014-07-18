use Module::Build;
Module::Build->new(
	module_name => 'App::gp',
	license     => 'perl',
	requires    => {
		'App::Cmd'        => 0,
		'File::HomeDir'   => 0,
		'File::chdir'     => 0,
		JSON              => 0,
		'App::Cmd::Plugin::Prompt' => 0,
		'File::Slurp'     => 0,
		'Math::Random'    => 0,
		'Time::ParseDate' => 0,
		'Safe::Isa'       => 0,
		'Clone'           => 0,
	},
)->create_build_script;