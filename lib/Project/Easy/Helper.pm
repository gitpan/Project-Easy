package Project::Easy::Helper;

use Class::Easy;

use IO::Easy;

use File::Spec;
my $FS = 'File::Spec';

our @scriptable = (qw(check_state));

sub ::initialize {
	my $name_space = shift @ARGV;

	my @path = ('lib', split '::', $name_space);
	my $last = pop @path;

	my $project_id = shift @ARGV || lc ($last);
	
	unless ($name_space) {
		die "please specify package namespace";
	}
	
	my $project_template = "package $name_space;

# \$Id\$

use strict;

use Project::Easy;
use base qw(Project::Easy);

use Class::Easy;

has 'id', default => '${project_id}';
has 'conf_format', default => 'json';

my \$class = __PACKAGE__;

has 'entity_prefix', default => join '::', \$class, 'Entity', '';

\$class->init;

# TODO: check why Project::Easy isn't provide db method
has 'db', default => sub {
	shift;
	return \$class->SUPER::db (\@_);
};

1;
";

	my $root = IO::Easy->new ('.');
	
	my $lib_dir = $root->append (@path)->as_dir;
	$lib_dir->create; # recursive directory creation	
	
	$last .= '.pm';
	my $class_file = $lib_dir->append ($last)->as_file;
	$class_file->store_if_empty ($project_template);
	
	# ok, project skeleton created. now we need to create config
	my $bin = $root->append ('bin')->as_dir;
	$bin->create;
	foreach (@scriptable) {
		my $script = $bin->append ($_)->as_file;
		chmod 0755, $script->name;
		$script->store_if_empty ("#!/usr/bin/perl
use strict;
use Project::Easy::Helper;
\&Project::Easy::Helper::$_;");
	}
	
	# ok, project skeleton created. now we need to create config
	my $etc = $root->append ('etc')->as_dir;
	$etc->append ('local')->as_dir->create;
	$etc->append ("$project_id.json")->as_file->store_if_empty ('{}');
	$etc->append ('local', "$project_id.json")->as_file->store_if_empty ('{}');
	$etc->append ('project-easy')->as_file->store_if_empty ("#!/usr/bin/perl
package LocalConf;
our \$pack = '$name_space';

our \@paths = qw(
);

1;
");
	
	my $var = $root->append ('var');
	foreach (qw(db lock log run)) {
		$var->append ($_)->as_dir->create;
	}
	
	my $distro = $var->append ('distribution')->as_file;
	$distro->store_if_empty ('local');
}

sub check_state {
	
	my ($pack, $libs) = &_script_wrapper;
	
	my $root = $pack->root;
	
	my $lib_dir = $root->append ('lib')->as_dir;
	
	my $includes = join ' ', map {"-I$_"} @$libs;

	$lib_dir->scan_tree (sub {
		my $file = shift;
		
		return 1 if $file->type eq 'dir';
		
		if ($file =~ /\.pm$/) {
			my $path = $file->rel_path ($root->path);

			print `perl -c $includes $path`;
			
			my $res = $? >> 8;
			if ($res == 0) {
				# print $path, " … OK\n";
			} elsif ($res == 255) {
				print $path, " … DIED\n";
				exit;
			} else {
				print $path, " … FAILED $res TESTS\n";
				exit;
			}
		}
	});

	my $test_dir = $root->append ('t')->as_dir;
	
	
	$test_dir->scan_tree (sub {
		my $file = shift;
		
		return 1
			if $file->type eq 'dir';
		
		if ($file =~ /\.(?:t|pl)$/) {
			my $path = $file->rel_path;
			
			print `perl $includes $path`;
			
			my $res = $? >> 8;
			if ($res == 0) {
				print $path, " … OK\n";
			} elsif ($res == 255) {
				print $path, " … DIED\n";
				exit;
			} else {
				print $path, " … FAILED $res TESTS\n";
				exit;
			}
		}
	});
	
	print "SUCCESS\n";
	
	return $pack;
	
}

sub _script_wrapper {
	my $local_conf = $0;
	my $lib_path;
	
	if (exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2) {
		use Apache2::ServerUtil;
		
		my $server_root = Apache2::ServerUtil::server_root();
		
		$local_conf = "$server_root/etc/project-easy";
		$lib_path   = "$server_root/lib";
		
	} else {
		$local_conf =~ s/(.*)(^|\/)(cgi-)?bin\/.*/$1$2etc\/project-easy/si;
		$lib_path = "$1$2lib";
	}
	
	unless ($FS->file_name_is_absolute ($lib_path)) {
		$lib_path = $FS->rel2abs ($lib_path);
	}
	
	warn "local conf is: $local_conf, lib path is: ", join ', ', @LocalConf::paths, $lib_path;
	
	require $local_conf;

	push @INC, @LocalConf::paths, $lib_path;
	
	my $pack = $LocalConf::pack;

	eval "
use $pack;
use IO::Easy;
use Class::Easy;
use DBI::Easy;
";

	if ($@) {
		print "something wrong with base modules: $@";
		exit;
	}
	
	return $pack, [@LocalConf::paths, $lib_path];
}


1;
