use ExtUtils::MakeMaker;

WriteMakefile(
	NAME => "Project::Easy",
	VERSION_FROM => "lib/Project/Easy.pm",
	'dist' => { COMPRESS=>"gzip", SUFFIX=>"gz" },
	AUTHOR => 'Ivan Baktsheev <dot.and.thing@gmail.com>',
	EXE_FILES => ["bin/project-easy"],
	PREREQ_PM => {
		'IO::Easy'    => 0,
		'Class::Easy' => 0,
		'DBI::Easy'   => 0,
		'JSON'        => 2.15,
	}
);
