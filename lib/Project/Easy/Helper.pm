package Project::Easy::Helper;

use Data::Dumper;
use Class::Easy;
use IO::Easy;
use IO::Easy::File;

use Getopt::Long;

use File::Spec;
my $FS = 'File::Spec';

our @scriptable = (qw(check_state config deploy shell db generate));

sub ::initialize {
	my $params = \@_;
	$params = \@ARGV
		unless scalar @$params;
	
	my $name_space = shift @$params;

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
	
	# ok, project skeleton created. now we need to create 'bin' dir
	my $bin = $root->append ('bin')->as_dir;
	$bin->create;
	
	# now we create several perl scripts to complete installation 
	foreach (@scriptable) {
		my $script = $bin->append ($_)->as_file;
		$script->store_if_empty ("#!/usr/bin/perl
use strict;
use Project::Easy::Helper;
\&Project::Easy::Helper::$_;\n");
		
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

	my ($package, $libs) = &_script_wrapper; # Project name and "libs" path
	
	my $root = $package->root;      # Absolute path to a project home
	my $core = $package->instance;  # Project instance
	
    my $config_package = $package->conf_package;        # Project::Easy::Config

	my $templates = IO::Easy::File::__data__files ();   # Got all "data files" at end of file
	
    # Init serializer to parse config file
    my $serializer_json = $config_package->serializer ('json');

    # Global config absolute path
	my $config_path  = $core->conf_path->as_file;
	
    # Local config absolute path
	my $local_config_path = $core->fixup_path_distro ($core->distro)->as_file;
	
    # Config now is a perl structure
	my $config  = $serializer_json->parse_string ( $config_path->contents );
    
    # And this too
    my $local_config  = $serializer_json->parse_string ( $local_config_path->contents );

    # How to print structure of config: compact or recursive Dumper-like
    my $recursive_dump = 0;
    
    GetOptions(
        'dump'    => \$recursive_dump
    );

    if ( scalar @ARGV < 1 ) {
        print $templates->{'config-usage'}, "\n";
        return;
    }
    else {
        my $config_key = $ARGV[0];
        
        my @key_parts = map { "{$_}" } split (/\./, $config_key);
        
        my $key = join '->', @key_parts; # $key = "{key1}->{key2}->{key3}..."
        
        if ( scalar @ARGV == 1 ) { # Print config key => value
        
            # Allow to "get" any key in configs: global and local
            Project::Easy::Config::patch($config, $local_config);
        
            my $perl_config_key = '$config' . '->' . $key;

            my $struct = eval $perl_config_key;
        
            # Check what kind of value we got: scalar or reference
            if ( ref $struct ) {
                
                if ( $recursive_dump ) {
                    print "$config_key => ", $serializer_json->dump_struct( $struct ), "\n";
                }
                else {
                    if    ( ref $struct eq 'ARRAY' ) {
                        print "Value is ARRAY with " . scalar @$struct . " elements\n";
                    }
                    elsif ( ref $struct eq 'HASH' ) {
                        print "Value is HASH with keys: " . join (', ', keys %$struct) . "\n";
                    }
                    else {
                        die 'Invalid struct';
                    }
                }
            }
            else {
                print "$config_key => ", eval $perl_config_key, "\n";   
            }
        }
        elsif ( scalar @ARGV == 3 ) { # Print config key => value
            my $action = $ARGV[1];
            #print Dumper($action, $new_value);
            
            if ( $action eq 'set'  ) { # Update key in configuration
                my $new_value = $ARGV[2];
                
                # Local config only
                my $perl_config_key = '$local_config' . '->' . $key;
                
                unless ( eval "exists $perl_config_key" ) {
                    print "Error: can not modify non-existent key!\n\n";
                    print $templates->{'config-usage'}, "\n";
                    return;
                }
                
                my $struct = eval $perl_config_key;
            
                unless ( ref $struct ) {
                    my $operator = $perl_config_key . ' = $new_value';
                    eval $operator; # DO here update of element
                    
                    # Store changes in local config
                    $local_config_path->store ($serializer_json->dump_struct($local_config));
                }
                else {
                    print "Error: can not update non-scalar element!\n\n";
                    print $templates->{'config-usage'}, "\n";
                    return;
                }
            }
            elsif ( $action eq 'template' ) { # Update block of configuration
                my $template_id = $ARGV[2];
                
                my ($new_config_section, $new_config_struct_key) = split /\./, $template_id;
                
                unless ( $new_config_section && $new_config_struct_key ) {
                    print "Error: incorrect template format!\n\n";
                    print $templates->{'config-usage'}, "\n";
                    return;
                }
                
                #print $templates->{'template-' . $template_id}, "\n";
                my $database_id = $ARGV[0];
        
                my (undef, $db_id) = split (/\./, $database_id);
                
                my $template = $serializer_json->parse_string ( $templates->{'template-' . $template_id} );
                my $patch_by_distribution = {};
                
                foreach my $config_option ( keys %$template ) {
                    my ($distribution, $option) = split(/:/, $config_option);
                    $patch_by_distribution->{$distribution}{db}{$db_id}{$option} = $template->{$config_option};
                }
                
                Project::Easy::Config::patch($config,  $patch_by_distribution->{global});
                Project::Easy::Config::patch($local_config, $patch_by_distribution->{local});
                
                $config_path->store ($serializer_json->dump_struct($config));
                $local_config_path->store ($serializer_json->dump_struct($local_config));
    
                return;
            }
        }
        else {
            print $templates->{'config-usage'}, "\n";
            return;
        }

    }
    #print Dumper($config);
    #print Dumper($local_config);
	
    return $package;
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
# $Id: Helper.pm,v 1.9 2009/07/20 17:53:49 apla Exp $

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


########################################
# IO::Easy::File config-params.json
########################################

{
	"add": {
		"database": {
            "DEFAULTS": {
                "global:opts": {
                    "RaiseError": 1,
                    "AutoCommit": 1,
                    "ShowErrorStatement": 1
                },
                "global:update": "share/sql/__FIXME__.sql"
            },
            "mysql": {
                "local:dsn": "DBI:mysql:database=$db_name",
                "local:user": "__FIXME__",
                "local:pass": "__FIXME__",
                "global:dsn_suffix": [
                    "mysql_multi_statements=1",
                    "mysql_enable_utf8=1",
                    "mysql_auto_reconnect=1",
                    "mysql_read_default_group=perl",
                    "mysql_read_default_file={$root}/etc/my.cnf"
                ]
            },
            "postgres": {
                "local:dsn": "DBI:postgres:database=$db_name",
                "local:user": "__FIXME__",
                "local:pass": "__FIXME__"
            }
		},
		"daemon": {
		
		}
	}
}

########################################
# IO::Easy::File config-usage
########################################

Usage:  db.<database_id> template db.<template_name>    OR
        db.<database_id>.username set "<password>"      OR
        db.<database_id>.username

Example (add new database config "local_test_db_id" with mysql template) :
./bin/config db.local_test_db_id template db.mysql

Example (change database config "local_test_db_id" from mysql to sqlite) :
./bin/config db.local_test_db_id template db.sqlite

########################################
# IO::Easy::File template-db.mysql
########################################

{
    "local:dsn": "DBI:mysql:database=$db_name",
    "local:user": "__FIXME__",
    "local:pass": "__FIXME__",
    "global:dsn_suffix": [
        "mysql_multi_statements=1",
        "mysql_enable_utf8=1",
        "mysql_auto_reconnect=1",
        "mysql_read_default_group=perl",
        "mysql_read_default_file={$root}/etc/my.cnf"
    ]
}

########################################
# IO::Easy::File template-db.default
########################################

{
    "local:dsn": "DBI:mysql:database=$db_name",
    "local:user": "__FIXME__",
    "local:pass": "__FIXME__",
    "global:dsn_suffix": [
        "Xmysql_multi_statements=1",
        "Xmysql_enable_utf8=1",
        "Xmysql_auto_reconnect=1",
        "Xmysql_read_default_group=perl",
        "Xmysql_read_default_file={$root}/etc/my.cnf"
    ]
}