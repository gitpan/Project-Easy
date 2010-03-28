use ExtUtils::MakeMaker;

WriteMakefile(
	NAME => "Project::Easy",
	VERSION_FROM => "lib/Project/Easy.pm",
	'dist' => { COMPRESS=>"gzip", SUFFIX=>"gz" },
	AUTHOR => 'Ivan Baktsheev <dot.and.thing@gmail.com>',
	EXE_FILES => ["bin/project-easy"],
	META_MERGE      => {
		resources => {
			license     =>      'http://dev.perl.org/licenses/',
			homepage    =>      'http://perlhug.com',
			bugtracker  =>      'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Project-Easy',
			repository  =>      'git://web-app.git.sourceforge.net/gitroot/perl-easy/perl-easy',
#			MailingList =>      'makemaker@perl.org',
		},
	},
	PREREQ_PM => {
		'IO::Easy'    => '0.13',
		'Class::Easy' => '0.11',
		'DBI::Easy'   => '0.16',
		'JSON'        => '2.16',
	}
);
