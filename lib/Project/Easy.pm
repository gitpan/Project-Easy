package Project::Easy;

use Class::Easy;
use IO::Easy;

use Project::Easy::Helper;
use Project::Easy::Config::File;

our $VERSION = '0.24';

# because singleton
our $singleton = {};

sub singleton {
	return $singleton;
}

has 'daemons', default => {};

has 'daemon_package', default => 'Project::Easy::Daemon';
has 'db_package',     default => 'Project::Easy::DB';
has 'conf_package',   default => 'Project::Easy::Config';

has 'etc', default => 'etc';
has 'bin', default => 'bin';

sub import {
	my $pack = shift;
	my @params = @_;
	
	if (scalar grep {$_ eq 'script'} @params) {
		Project::Easy::Helper::_script_wrapper;

		Class::Easy->import;
		IO::Easy->import;
	
	} elsif (scalar grep {$_ eq 'project'} @params) {
		Project::Easy::Helper::_script_wrapper (undef, 1);
	
	}
}

sub init {
	my $class = shift;
	
	my $conf_package = $class->conf_package;
	try_to_use ($conf_package)
		or die ('configuration package must exists');
	
	$class->attach_paths;
	
	my $root = dir ($class->lib_path)->parent;

	make_accessor ($class, 'root', default => $root);
	
	my $conf_path = $root->append ($class->etc, $class->id . '.' . $class->conf_format)->as_file;
	
	die "can't locate generic config file at '$conf_path'"
		unless -f $conf_path;

	# blessing for functionality extension: serializer
	$conf_path = bless ($conf_path, 'Project::Easy::Config::File');

	make_accessor ($class, 'conf_path', default => $conf_path);
	
}

sub instantiate {
	my $class = shift;
	
	die "you cannot use Project::Easy in one project more than one time ($singleton->{_instantiated})"
		if $singleton->{_instantiated};
	
	debug "here we try to detect package location, "
		. "because this package isn't for public distribution "
		. "and must live in <project directory>/lib";
		
	$class->detect_environment;

	my $db_package = $class->db_package;
	try_to_use ($db_package);
	
	bless $singleton, $class;
	
	$singleton->{_instantiated} = $class;

	my $config = $singleton->config;

	foreach my $db_id (keys %{$config->{db}}) {
		make_accessor ($class, "db_$db_id", default => sub {
			return $class->db ($db_id);
		});
	}
	
	if (exists $config->{daemons}) {
		
		my $d_pack = $class->daemon_package;
		try_to_use ($d_pack);
	
		foreach my $d_name (keys %{$config->{daemons}}) {
			my $d_conf = $config->{daemons}->{$d_name};
			
			my $d;
			
			if ($d_conf->{package}) {
				try_to_use ($d_conf->{package});
				$d = $d_conf->{package}->new ($singleton, $d_name, $d_conf);
			} else {
				$d = $d_pack->new ($singleton, $d_name, $d_conf);
			}
			
			
			
			$singleton->daemons->{$d_name} = $d;
		}
	}
	
	return $singleton;
}

sub detect_environment {
	my $class = shift;
	
	my $root = $class->root;
	
	my $distro_path = $root->append ('var', 'distribution');
	
	die "\$project_root/var/distribution not found"
		unless -f $distro_path;
	
	my $distro_string = $distro_path->as_file->contents;
	
	chomp $distro_string;

	die "can't recognise distribution '$distro_string'"
		unless $distro_string;
	
	my ($distro, $fixup_core) = split (/:/, $distro_string, 2);
	
	make_accessor ($class, 'distro', default => $distro);
	make_accessor ($class, 'fixup_core', default => $fixup_core);
	
	my $fixup_path = $class->fixup_path_distro;

	die "can't locate fixup config file at '$fixup_path'"
		unless -f $fixup_path;
	
	make_accessor ($class, 'fixup_path', default => $fixup_path);
	
}

sub fixup_path_distro {
	my $self   = shift;
	my $distro = shift || $self->distro;
	
	my $fixup_core = $self->fixup_core;
	
	my $fixup_path;
	
	if (defined $fixup_core and $fixup_core) {
		$fixup_path = IO::Easy->new ($fixup_core)->append ($distro);
	} else {
		$fixup_path = $self->root->append ($self->etc, $distro);
	}
	
	$fixup_path = $fixup_path->append ($self->id . '.' . $self->conf_format)->as_file;
	
	bless ($fixup_path, 'Project::Easy::Config::File');
}

sub config {
	my $class = shift;
	
	if (@_ > 0) { # get config for another distro, do not cache
		my $config = $class->conf_package->parse (
			$singleton, @_
		);
		
		# reparse config
		if ($_[0] eq $class->distro) {
			$singleton->{config} = $config
		}
		
		return $config
	}
	
	unless ($singleton->{config}) {
		$singleton->{config} = $class->conf_package->parse (
			$singleton
		);
	}
	
	return $singleton->{config};
}

sub _detect_entity {
	my $self = shift;
	my $name = shift;

	# TODO: move methods from DBI::Easy::Helper
	
	my $qname      = DBI::Easy::Helper::package_from_table ($name);
	my $table_name = DBI::Easy::Helper::table_from_package ($qname);
	
	my $db_prefix = '';
	
	foreach my $k (grep {!/^default$/} keys %{$self->config->{db}}) {
		my $qk = DBI::Easy::Helper::package_from_table ($k);
		if (index ($qname, $qk) == 0) {
			$db_prefix = $qk;
			$table_name = DBI::Easy::Helper::table_from_package (substr ($qname, length ($db_prefix)));
			last;
		}
		# $db_prefix = (split /(?=\p{IsUpper}\p{IsLower})/, DBI::Easy::Helper::package_from_table ($qname))[0];
		
	}
	
	# warn "$name: $qname, $table_name, $db_prefix";
	
	return ($qname, $table_name, $db_prefix);
}

sub entity {
	my $self = shift;
	my $name = shift;
	
	# TODO: make cache for entities
	
	# try to detect entity by prefix
	my ($qname, $entity_name, $datasource_prefix) = $self->_detect_entity ($name);
	
	my $datasource_config = $self->config->{db}->{$datasource_prefix};
	
	my $datasource_package = $datasource_config->{package} || $self->db_package;
	
	$datasource_package->entity ($name, $qname, $entity_name, $datasource_prefix);
}

sub collection {
	my $self = shift;
	my $name = shift;
	
	# TODO: make cache for entities
	
	# try to detect entity by prefix
	my ($qname, $entity_name, $datasource_prefix) = $self->_detect_entity ($name);
	
	my $datasource_config = $self->config->{db}->{$datasource_prefix};
	
	my $datasource_package = $datasource_config->{package} || $self->db_package;
	
	$datasource_package->collection ($name, $qname, $entity_name, $datasource_prefix);
}


sub daemon {
	my $core = shift;
	my $code = shift;
	
	return $core->daemons->{$code};
}

sub db { # TODO: rewrite using alert 
	my $class = shift;
	my $type  = shift || 'default';
	
	my $core = $class->singleton; # fetch current process singleton
	
	$core->{db}->{$type} = {ts => {}}
		unless $core->{db}->{$type};
	
	my $current_db = $core->{db}->{$type};

	my $db_package = $core->config->{db}->{$type}->{package} || $core->db_package;

	unless ($current_db->{$$}) {
		
		$DBI::Easy::ERRHANDLER = sub {
			debug '%%%%%%%%%%%%%%%%%%%%%% DBI ERROR: we relaunch connection %%%%%%%%%%%%%%%%%%%%%%%%';
			debug 'ERROR: ', $@;
			
			my $old_dbh = delete $current_db->{$$};

			$old_dbh->disconnect
				if $old_dbh;

			$current_db->{$$} = $db_package->new ($core, $type);
			$current_db->{ts}->{$$} = time;
			
			return $class->db ($type);
		};
		
		my $t = timer ("database handle start");
		$current_db->{$$} = $db_package->new ($core, $type);
		$current_db->{ts}->{$$} = time;
		$t->end;
		
	}
	
	# we reconnect every hour
	if ((time - $current_db->{ts}->{$$}) > 3600) {
		my $old_dbh = delete $current_db->{$$};
		
		$old_dbh->disconnect
			if $old_dbh;
		
		$current_db->{$$} = $db_package->new ($core, $type);
		$current_db->{ts}->{$$} = time;
	}
	
	return $current_db->{$$};
	
}



1;

=head1 NAME

Project::Easy - project deployment made easy.

=head1 SYNOPSIS

	package Caramba;

	use Class::Easy;

	use Project::Easy;
	use base qw(Project::Easy);

	has 'id', default => 'caramba';
	has 'conf_format', default => 'json';

	my $class = __PACKAGE__;

	has 'entity_prefix', default => join '::', $class, 'Entity', '';

	$class->init;

=head1 ACCESSORS

=head2 singleton

=over 4

=item singleton

return class instance

=cut 

=head2 configurable options

=over 4

=item id

project id

=item conf_format

default config file format

=item daemon_package

interface for daemon creation

default => 'Project::Easy::Daemon'

=item db_package

interface for db connections creation

default => 'Project::Easy::DB'

=item conf_package

configuration interface

default => 'Project::Easy::Config';

=item default configuration directory

has 'etc', default => 'etc';

=item default binary directory

has 'bin', default => 'bin';

=cut

=head2 autodetect options

=over 4

=item root

IO::Easy object for project root directory

=item distro

string contains current distribution name

=item fixup_core

path (string) to configuration fixup root

=item conf_path

path object to the global configuration file

=item fixup_path

path object to the local configuration file

=cut

=head1 METHODS

=head2 config

return configuration object

=head2 db

database pool

=cut

=head1 ENTITIES

=over 4

=item intro

Project::Easy create default entity classes on initialization.
this entity based on default database connection. you can use
this connection (not recommended) within modules by mantra:

	my $core = <project_namespace>->singleton;
	my $dbh = $core->db;

method db return default $dbh. you can use non-default dbh named 'cache' by calling:

	my $dbh_cache = $core->db ('cache');

or
	my $dbh_cache = $core->db_cache;

if DBI::Easy default API satisfy you, then you can use database entities
by calling

	my $account_record = $core->entity ('Account');
	my $account_collection = $core->collection ('Account');
	
	my $all_accounts = $account_collection->new->list;

in this case, virtual packages created for entity 'account'.

or you can create these packages by hand:

	package <project_namespace>::Entity::Account;
	
	use Class::Easy;
	
	use base qw(<project_namespace>::Entity::Record);
	
	1;

and for collection:

	package <project_namespace>::Entity::Account::Collection;

	use Class::Easy;

	use base qw(<project_namespace>::Entity::Collection);

	1;

in this case

	my $account_record = $core->entity ('Account');
	my $account_collection = $core->collection ('Account');
	
also works for you

=cut 

=item creation another database entity class

TODO: creation by script

=cut 

=item using entities from multiple databases

TODO: read database tables and create entity mappings,
each entity subclass must contain converted database identifier:

	default entity, table account_settings => entity AccountSettings
	'cache' entity, table account_settings => entity CacheAccountSettings
 

=cut 


=head1 AUTHOR

Ivan Baktsheev, C<< <apla at the-singlers.us> >>

=head1 BUGS

Please report any bugs or feature requests to my email address,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Project-Easy>. 
I will be notified, and then you'll automatically be notified
of progress on your bug as I make changes.

=head1 SUPPORT



=head1 ACKNOWLEDGEMENTS



=head1 COPYRIGHT & LICENSE

Copyright 2007-2009 Ivan Baktsheev

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut
