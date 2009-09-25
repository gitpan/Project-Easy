package Project::Easy::Helper;

use Class::Easy;

use IO::Easy;
use IO::Easy::File;

use File::Spec;
my $FS = 'File::Spec';

our @scriptable = (qw(check_state config deploy shell db generate));

sub ::initialize {
	my $name_space = shift @ARGV;

	my @path = ('lib', split '::', $name_space);
	my $last = pop @path;

	my $project_id = shift @ARGV || lc ($last);
	
	unless ($name_space) {
		die "please specify package namespace";
	}
	
	my $project_template = IO::Easy::File::__data__files->{'Project.pm'};
	
	my $data = {
		name_space => $name_space,
		project_id => $project_id,
	};
	
	$project_template =~ s/\{\$(\w+)\}/$data->{$1}/g;
	
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
		$script->store_if_empty ("#!/usr/bin/perl
use strict;
use Project::Easy::Helper;
\&Project::Easy::Helper::$_;");
		
		warn  "can't chmod " . $script->path
			unless chmod 0755, $script->path;
		
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

	my $t = $root->append ('t')->as_dir;
	$t->create;

}

sub run_script {
	my $script = shift;
	my $path   = shift;
	
	print `$script`;
	
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

sub check_state {
	
	my ($pack, $libs) = &_script_wrapper;
	
	my $root = $pack->root;
	
	my $lib_dir = $root->append ('lib')->as_dir;
	
	my $includes = join ' ', map {"-I$_"} @$libs;
	
	my $files = [];
	my $all_uses = {};
	my $all_packs = {};
	
	$lib_dir->scan_tree (sub {
		my $file = shift;
		
		return 1 if $file->type eq 'dir';
		
		if ($file =~ /\.pm$/) {
			push @$files, $file;
			my $content = $file->contents;

			while ($content =~ m/^(use|package) ([^\$\;\s]+)/igms){
				if ($1 eq 'use') {
					$all_uses->{$2} = $file;
				} else {
					$all_packs->{$2} = $file;
				}
			}
		}
	});
	
	foreach (keys %$all_uses) {
		delete $all_uses->{$_}
			if /^[a-z][a-z0-9]+$/;
	}
	
	my $failed   = {};
	my $external = {};
	
	# here we try to find dependencies
	foreach (keys %$all_uses) {
		#warn "TRY TO USE: $_ : " . try_to_use ($_) . "\n"
		#	if ! /^Rian\:\:/;
		$external->{$_} = $all_uses->{$_}
			unless exists $all_packs->{$_};
		
		$failed->{$_} = $all_uses->{$_}
			if ! try_to_use ($_) and ! exists $all_packs->{$_};
	}
	
	warn "external modules: ", join ' ', sort keys %$external;
	
	warn "requirements not satisfied. you must install these modules:\ncpan -i ",
		join (' ', sort keys %$failed), "\n"
			if scalar keys %$failed;
	
	foreach my $file (@$files) {
		my $path = $file->rel_path ($root->path);
		
		print run_script ("perl -c $includes $path", $path);
		
	}

	my $test_dir = $root->append ('t')->as_dir;
	
	$test_dir->scan_tree (sub {
		my $file = shift;
		
		return 1
			if $file->type eq 'dir';
		
		if ($file =~ /\.(?:t|pl)$/) {
			my $path = $file->rel_path;
			
			print run_script ("perl $includes $path", $path);
		}
	});
	
	print "SUCCESS\n";
	
	return $pack;
	
}

sub shell {
	my ($pack, $libs) = &_script_wrapper;
	
	my $core = $pack->instance;
	
	my $distro = $ARGV[0];
	
	my $conf  = $core->config ($distro);
	my $sconf = $conf->{shell};
	
	unless (try_to_use 'Net::SSH::Perl' and try_to_use 'Term::ReadKey') {
		die "for remote shell you must install Net::SSH::Perl and Term::ReadKey packages";
	}
	
	my %args = ();
	foreach (qw(compression cipher port debug identity_files use_pty options protocol)) {
		$args{$_} = $sconf->{$_}
			if $sconf->{$_};
	}
	
	$args{interactive} = 1;
	
	my $ssh = Net::SSH::Perl->new ($conf->{host}, %args);
	$ssh->login ($sconf->{user});
	
	ReadMode('raw');
	eval "END { ReadMode('restore') };";
	$ssh->shell;

}

sub db {
	my ($pack, $libs) = &_script_wrapper;
	
	my $root = $pack->root;
	
	my $config = $pack->config;
	
	
}

sub config {
	
	my ($pack, $libs) = &_script_wrapper;
	
	my $root = $pack->root;
	
	my $commands = {
		add => {
			database => {
				'' => {
					"global:opts" => {
						RaiseError => 1,
						AutoCommit => 1,
						ShowErrorStatement => 1
					},
					"global:update" => "share/sql/__FIXME__.sql"
				},
				mysql => {
					"local:dsn" => "DBI:mysql:database=__FIXME__",
					"local:user" => "__FIXME__",
					"local:pass" => "__FIXME__",
					"global:dsn_suffix" => [
						"mysql_multi_statements=1",
						"mysql_enable_utf8=1",
						"mysql_auto_reconnect=1",
						"mysql_read_default_group=perl",
						"mysql_read_default_file={$root}/etc/my.cnf"
					],
				}
			},
			daemon => {
			
			},
		},
	};
	
	my $lib_dir = $root->append ('lib')->as_dir;
	
	my $includes = join ' ', map {"-I$_"} @$libs;

	my $scan_handler = sub {
		my $file = shift;
		
		return 1 if $file->type eq 'dir';
		
		if ($file =~ /\.(?:pm|pl|t)$/) {
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
	};
	
	$lib_dir->scan_tree ($scan_handler);

	my $test_dir = $root->append ('t')->as_dir;
	
	$test_dir->scan_tree ($scan_handler);
	
	print "SUCCESS\n";
	
	return $pack;
	
}


sub _script_wrapper {
	# because some calls dispatched to external scripts, but called from project dir
	my $local_conf = shift || $0; 
	my $lib_path;
	
	debug "called from $local_conf";
	
	if (
		exists $ENV{MOD_PERL_API_VERSION}
		and $ENV{MOD_PERL_API_VERSION} >= 2
		and try_to_use ('Apache2::ServerUtil')
	) {
		
		my $server_root = Apache2::ServerUtil::server_root();
		
		$local_conf = "$server_root/etc/project-easy";
		$lib_path   = "$server_root/lib";
		
	} else {
		$local_conf =~ s/(.*)(^|\/)(?:cgi-bin|tools|bin)\/.*/$1$2etc\/project-easy/si;
		$lib_path = "$1$2lib";
	}
	
	unless ($FS->file_name_is_absolute ($lib_path)) {
		$lib_path = $FS->rel2abs ($lib_path);
	}
	
	# TODO: try other dirs
	$local_conf =~ s/etc\//conf\//
		unless -f $local_conf;
	
	debug "local conf is: $local_conf, lib path is: ",
		join (', ', @LocalConf::paths, $lib_path), "\n";
	
	require $local_conf;

	push @INC, @LocalConf::paths, $lib_path;
	
	my $pack = $LocalConf::pack;
	
	debug "main project module is: $pack";
	
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
	
	my @result = ($pack, [@LocalConf::paths, $lib_path]);
	return @result;
}


1;


__DATA__

########################################
# IO::Easy::File Project.pm
########################################

package {$name_space};
# $Id: Helper.pm,v 1.1 2009/07/20 18:00:08 apla Exp $

use Class::Easy;

use Project::Easy;
use base qw(Project::Easy);

has 'id', default => '{$project_id}';
has 'conf_format', default => 'json';

my $class = __PACKAGE__;

has 'entity_prefix', default => join '::', $class, 'Entity', '';

$class->init;

# TODO: check why Project::Easy isn't provide db method
has 'db', default => sub {
	shift;
	return $class->SUPER::db (@_);
};

1;

########################################
# IO::Easy::File template
########################################
