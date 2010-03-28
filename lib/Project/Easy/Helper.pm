package Project::Easy::Helper;

use Data::Dumper;
use Class::Easy;
use IO::Easy;

use Time::Piece;

use Project::Easy::Config;
use Project::Easy::Helper::DB;

our @scriptable = (qw(status config updatedb));

sub ::initialize {
	my $params = \@_;
	$params = \@ARGV
		unless scalar @$params;
	
	my $namespace = shift @$params;

	my @path = ('lib', split '::', $namespace);
	my $last = pop @path;

	my $project_id = shift @ARGV || lc ($last);
	
	debug "initialization of $namespace, project id is: $project_id";
	
	unless ($namespace) {
		die "please specify package namespace";
	}
	
	my $data_files = file->__data__files;
	
	my $data = {
		namespace => $namespace,
		project_id => $project_id,
	};
	
	my $project_pm = Project::Easy::Config::string_from_template (
		$data_files->{'Project.pm'},
		$data
	);

	my $login = eval {scalar getpwuid ($<)};

	my $distribution = 'local' . (defined $login ? ".$login" : '');
	
	my $root = dir->current;
	
	my $lib_dir = $root->append (@path)->as_dir;
	$lib_dir->create; # recursive directory creation	
	
	$last .= '.pm';
	my $class_file = $lib_dir->append ($last)->as_file;
	$class_file->store_if_empty ($project_pm);
	
	# ok, project skeleton created. now we need to create 'bin' dir
	my $bin = $root->append ('bin')->as_dir;
	$bin->create;
	
	# now we create several perl scripts to complete installation 
	foreach (@scriptable) {
		my $script = $bin->append ($_)->as_file;

		my $script_contents = Project::Easy::Config::string_from_template (
			$data_files->{'script.template'},
			{script_name => $_}
		);

		$script->store_if_empty ($script_contents);
		
		warn  "can't chmod " . $script->path
			unless chmod 0755, $script->path;
		
	}
	
	# ok, project skeleton created. now we need to create config
	my $etc = $root->append ('etc')->as_dir;
	$etc->append ($distribution)->as_dir->create;
	
	# TODO: store database config
	$etc->append ("$project_id.json")->as_file->store_if_empty ('{}');
	$etc->append ($distribution, "$project_id.json")->as_file->store_if_empty ('{}');
	
	$etc->append ('project-easy')->as_file->store_if_empty ("#!/usr/bin/perl
package LocalConf;
our \$pack = '$namespace';

our \@paths = qw(
);

1;
");
	
	my $var = $root->append ('var');
	foreach (qw(db lock log run)) {
		$var->append ($_)->as_dir->create;
	}
	
	my $distro = $var->append ('distribution')->as_file;
	$distro->store_if_empty ($distribution);

	my $t = $root->append ('t')->as_dir;
	$t->create;
	
	my @namespace_chunks = split /\:\:/, $namespace;
	
	# here we must create default entity classes
	my $project_lib = $root->append ('lib', @namespace_chunks, 'Entity');
	$project_lib->as_dir->create;

	my $entity_template = $data_files->{'Entity.pm'};

	my $entity_pm = Project::Easy::Config::string_from_template (
		$entity_template,
		{
			%$data,
			scope => 'Record',
			dbi_easy_scope => 'Record'
		}
	);

	$project_lib->append ('Record.pm')->as_file->store ($entity_pm);

	$entity_pm = Project::Easy::Config::string_from_template (
		$entity_template,
		{
			%$data,
			scope => 'Collection',
			dbi_easy_scope => 'Record::Collection'
		}
	);

	$project_lib->append ('Collection.pm')->as_file->store ($entity_pm);
	
	# adding sqlite database (sqlite is dependency for dbi::easy)
	
	debug "file contents saving done";
	
	$0 = dir->current->append (qw(etc project-easy))->path;
	
	my $date = localtime->ymd;
	
	my $schema_file = file ('share/sql/default.sql');
	$schema_file->parent->create;
	$schema_file->store (
		"--- $date\ncreate table var (var_name text, var_value text);\n"
	);

	config (qw(db.default template db.sqlite));
	config (qw(db.default.attributes.dbname = ), '{$root}/var/test.sqlite');
	config (qw(db.default.update =), "$schema_file");
	
	$namespace->config ($distribution);
	
	update_schema (
		mode => 'install'
	);
	
	# TODO: be more user-friendly: show help after finish
	
}

sub run_script {
	my $script = shift;
	my $path   = shift;
	
	# print `$script`;
	
	my $res = $? >> 8;
	if ($res == 0) {
		debug $path, " … OK\n";
	} elsif ($res == 255) {
		warn $path, " … DIED\n";
		exit;
	} else {
		warn $path, " … FAILED $res TESTS\n";
		exit;
	}
}

sub status {
	my ($project_class, $libs);
	
	eval {
		($project_class, $libs) = &_script_wrapper;
	};
	
	my $distro_not_found = '\$project_root/var/distribution not found';
	
	if ($@ =~ /^$distro_not_found/) {
		# we need to show user an option to replay project configuration
		
		&status_fail ($project_class, $libs);
		
		die "$distro_not_found;
probably you have cloned or checked out project from repository;
if that's right, please run this command with --fix option to fix environment";
	} elsif ($@) {
		die $@;
	}
	
	return &status_ok ($project_class, $libs);
	
}

sub status_fail {
	my ($project_class, $libs, $params) = @_;
	
	my $root = $project_class->root;
	
	# here we must recreate var directories
	# TODO: make it by Project::Easy::Helper service 'install' routine
	
	my $global_config = $project_class->conf_path->deserialize;
}

sub status_ok {
	my ($pack, $libs, $params) = @_;
	
	my $root = $pack->root;
	
	my $lib_dir = $root->append ('lib')->as_dir;
	
	my $includes = join ' ', map {"-I$_"} (@$libs, @INC);
	
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
		$external->{$_} = $all_uses->{$_}
			unless exists $all_packs->{$_};
		
		$failed->{$_} = $all_uses->{$_}
			if ! try_to_use ($_) and ! exists $all_packs->{$_};
	}
	
	debug "external modules: ", join (' ', sort keys %$external), "\n";
	
	warn "requirements not satisfied. you must install these modules:\ncpan -i ",
		join (' ', sort keys %$failed), "\n"
			if scalar keys %$failed;
	
	foreach my $file (@$files) {
		my $abs_path = $file->abs_path;
		my $rel_path = $file->rel_path ($root->rel_path);

		# warn "$^X -c $includes $abs_path";
		
		print run_script ("$^X -c $includes $abs_path", $rel_path);
		
	}

	my $test_dir = $root->append ('t')->as_dir;
	
	$test_dir->scan_tree (sub {
		my $file = shift;
		
		return 1
			if $file->type eq 'dir';
		
		if ($file =~ /\.(?:t|pl)$/) {
			my $path = $file->abs_path;
			
			print run_script ("$^X $includes $path", $path);
		}
	});
	
	print "SUCCESS\n";
	
	return $pack;
}

sub shell {
	my ($pack, $libs) = &_script_wrapper;
	
	my $core = $pack->singleton;
	
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

sub config {
	
	my @params = @ARGV;
	@params = @_
		if scalar @_;
	
	my ($package, $libs) = &_script_wrapper(); # Project name and "libs" path
	
	my $core   = $package->singleton;  # Project singleton
	my $config = $core->config;
	
	my $templates = file->__data__files ();   # Got all "data files" at end of file

	my ($key, $command, @remains) = @params;
	
	unless (defined $key) {
		print $templates->{'config-usage'}, "\n";
		return;
	}
	
	#  $key      = "key1.key2.key3..."
	#  $key_eval = "{key1}->{key2}->{key3}..."
	my $key_path = "{" . join ('}->{', split (/\./, $key)) . '}';
	my $key_eval = "\$config->$key_path";

	my $struct     = eval $key_eval;
	my $ref_struct = ref $struct;

	if (!defined $command or ($command eq 'dump' and !$ref_struct)) {
		print "'$key' => ";
		
		if ($ref_struct eq 'HASH') {
			print "HASH with keys: ", join ', ', keys %$struct;
		
		} elsif ($ref_struct eq 'ARRAY') {
			print "ARRAY of ", scalar @$struct;
		
		} elsif (!$ref_struct) {
			print "'", (defined $struct ? $struct : 'null'), "'";
		}
		print "\n";
		return 1;
	}

	my $conf_package = $package->conf_package;		# Project::Easy::Config

	# Init serializer to parse config file
	my $serializer_json = $conf_package->serializer ('json');
	
	if ($command =~ /^(?:--)?dump$/) {
		print "'$key' => ";
		print $serializer_json->dump_struct ($struct);
		print "\n";
		return 1;
	}
	
	# set or = can: create new key (any depth), modify existing
	# template can: create new key (any depth)
	if ($command eq 'set' or $command eq '=' or $command eq 'template') {
		
		die "you must supply value for modify config"
			unless scalar @remains;
		
		# check for legitimity
		die "you cannot set/template complex value such as HASH/ARRAY. remove old key first"
			if $ref_struct;
		
		die "you cannot update scalar value with template. remove old key first"
			if $command eq 'template' and defined $struct; # any setter
		
		# patch creation for config files
		
		my $fixup_struct = {};
		
		if ($command eq 'template') {

			my $template = $serializer_json->parse_string (
				$templates->{'template-' . $remains[0]}
			);
			
			eval "\$fixup_struct->$key_path = \$template";
		} else {
			eval "\$fixup_struct->$key_path = \$remains[0]";
		}
        
		
		# storing modified config

		# Global config absolute path
		my $global_config_file = $core->conf_path;
		$global_config_file->patch ($fixup_struct, 'undef_keys_in_patch');
        #warn(Dumper($global_config_file->contents));
		
        # Local config absolute path
		my $local_config_file  = $core->fixup_path_distro ($core->distro);
		$local_config_file->patch ($fixup_struct);
        #warn(Dumper($local_config_file->contents));

		return 1;
	}

	print $templates->{'config-usage'}, "\n";
	
	return;
}

sub _script_wrapper {
	# because some calls dispatched to external scripts, but called from project dir
	my $local_conf = shift || $0;
	my $importing  = shift ||  0;
	my $lib_path;
	
	return ($::project, $::libs)
		if defined $::project;

	debug "called from $local_conf";
	
	$local_conf = dir ($local_conf);

	if (exists $ENV{'MOD_PERL'}) {
		
		my $server_root;
		
		if (
			exists $ENV{MOD_PERL_API_VERSION}
			and $ENV{MOD_PERL_API_VERSION} >= 2
			and try_to_use_inc ('Apache2::ServerUtil')
		) {
			
			$server_root = Apache2::ServerUtil::server_root();
			
		} elsif (try_to_use_inc ('Apache')) {
			
			$server_root = Apache::server_root_relative('');
			
		} else {
			die "you try to run project::easy under mod_perl, but we cannot work with your version. if you have mod_perl-1.99, use solution from CGI::minimal or upgrade your mod_perl";
		}
		
		$local_conf = dir ($server_root)->dir_io (qw(etc project-easy));
		$lib_path   = dir ($server_root)->dir_io ("lib");
		
	} elsif ($local_conf->name eq 'project-easy' and $local_conf->parent->name eq 'etc') {
		$lib_path = $local_conf->parent->parent->dir_io ('lib');
	} else {
		my $root;
		my $parent = $local_conf;
		PROJECT_ROOT: while ($parent = $parent->parent) {
			
			foreach (qw(t cgi-bin tools bin)) {
				if ($parent->name eq $_) {
					$root = $parent->parent;
					$local_conf = $root->file_io (qw(etc project-easy));
					$lib_path = $root->dir_io ('lib');
					last PROJECT_ROOT;
				}
			}
		}
		die unless defined $root;
	}
	
	$lib_path = $lib_path->abs_path;
	
	debug "local conf is: $local_conf, lib path is: ",
		join (', ', @LocalConf::paths, $lib_path), "\n";
	
	require $local_conf;

	push @INC, @LocalConf::paths, $lib_path->path;
	
	my $pack = $LocalConf::pack;
	
	debug "main project module is: $pack";

	#use Carp;
	#$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };
	
	eval "use Class::Easy; use IO::Easy; use DBI::Easy; " . ($importing ? '' : "use $pack;");
	if ($@) {
		die 'base modules fails: ', $@;
	}

	my @result = ($::project, $::libs) = ($pack, [@LocalConf::paths, $lib_path->path]);
	
	return @result;
}


1;


__DATA__

########################################
# IO::Easy::File Project.pm
########################################

package {$namespace};

use Class::Easy;

use base qw(Project::Easy);

has id => '{$project_id}';
has conf_format => 'json';

my $class = __PACKAGE__;

has entity_prefix => join '::', $class, 'Entity', '';

$class->init;
$class->instantiate;

1;

########################################
# IO::Easy::File script.template
########################################

#!/usr/bin/perl
use Class::Easy;
use Project::Easy::Helper;
&Project::Easy::Helper::{$script_name};

########################################
# IO::Easy::File Entity.pm
########################################

package {$namespace}::Entity::{$scope};

use Class::Easy;

use base qw(DBI::Easy::{$dbi_easy_scope});

our $wrapper = 1;

sub _init_db {
	my $self = shift;
	
	$self->dbh ($::project->can ('db_default'));
}

1;

########################################
# IO::Easy::File template
########################################


########################################
# IO::Easy::File config-usage
########################################

Usage:  db.<database_id> template db.<template_name>	OR
		db.<database_id>.username set "<password>"	  OR
		db.<database_id>.username

Example (add new database config "local_test_db_id" with mysql template) :
./bin/config db.local_test_db_id template db.mysql

########################################
# IO::Easy::File template-db.sqlite
########################################

{
	"driver_name": "SQLite",
	"attributes": {
		"dbname" : null
	},
	"options": {
		"RaiseError": 1,
		"AutoCommit": 1,
		"ShowErrorStatement": 1
	}
}


########################################
# IO::Easy::File template-db.mysql
########################################

{
	"user": null,
	"pass": null,
	"driver_name": "mysql",
	"attributes": {
		"database" : null,
		"mysql_multi_statements": 0,
		"mysql_enable_utf8": 1,
		"mysql_auto_reconnect": 1,
		"mysql_read_default_group": "perl",
		"mysql_read_default_file": "{$root}/etc/my.cnf"
	},
	"options": {
		"RaiseError": 1,
		"AutoCommit": 1,
		"ShowErrorStatement": 1
	}
}

########################################
# IO::Easy::File template-db.default
########################################
{
	"user": null,
	"pass": null,
	"driver_name": null, // mysql, oracle, pg, …
	"attributes": {
		"database" : null
	},
	"options": {
		"RaiseError": 1,
		"AutoCommit": 1,
		"ShowErrorStatement": 1
	}
}
