package Project::Easy;

# $Id: Easy.pm,v 1.1 2009/07/20 18:00:09 apla Exp $

use Class::Easy;
use IO::Easy;

use Project::Easy::Helper;

use vars qw($VERSION);

$VERSION = '0.09.01';

# because singletone
our $instance = {};

sub instance {
	return $instance;
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

		($::pack, $::libs) = Project::Easy::Helper::_script_wrapper;
		push @INC, @$::libs;
	}
}

sub init {
	my $class = shift;
	
	die "you cannot use Project::Easy in one project more than one time ($instance->{_initialized})"
		if $instance->{_initialized};
	
	my $conf_package = $class->conf_package;
	try_to_use ($conf_package)
		or die ('configuration package must exists');
	
	debug "here we try to detect package location, "
		. "because this package isn't for public distribution "
		. "and must live in <project directory>/lib";
		
	$class->detect_environment;

	my $db_package = $class->db_package;
	try_to_use ($db_package);

	bless $instance, $class;
	
	$instance->{_initialized} = $class;

	my $config = $instance->config;
	
	if (exists $config->{daemons}) {
		
		my $d_pack = $class->daemon_package;
		try_to_use ($d_pack);
	
		foreach my $d_name (keys %{$config->{daemons}}) {
			my $d_conf = $config->{daemons}->{$d_name};
			
			my $d = $d_pack->new ($instance, $d_name, $d_conf);
			
			$instance->daemons->{$d_name} = $d;
		}
	}
	
	return $instance;
}

sub entity {
	my $self = shift;
	my $name = shift;
	
	my $package = join '', $self->entity_prefix, $name;
	
	die "can't require $package"
		unless try_to_use ($package);
	
	return $package;
}

sub collection {
	my $self = shift;
	my $name = shift;
	
	my $package = join '', $self->entity_prefix, $name, '::Collection';
	
	die "can't require $package"
		unless try_to_use ($package);
	
	return $package;
}


sub detect_environment {
	my $class = shift;
	
	attach_paths ($class);
	
	my $root = IO::Easy->new (($class->lib_path =~ /(.*)lib$/)[0]);
	
	make_accessor ($class, 'root', default => $root);

	my $distro_path = $root->append ('var', 'distribution');
	my $distro_string = $distro_path->as_file->contents;
	
	chomp $distro_string;

	die "can't recognise distribution '$distro_string'"
		unless $distro_string;
	
	my ($distro, $fixup_core) = split (/:/, $distro_string, 2);
	
	make_accessor ($class, 'distro', default => $distro);
	make_accessor ($class, 'fixup_core', default => $fixup_core);
	
	try_to_use ('Project::Easy::Config::File');
	
	my $conf_path = $root->append ($class->etc, $class->id . '.' . $class->conf_format)->as_file;
	
	die "can't locate generic config file at '$conf_path'"
		unless -f $conf_path;
	
	# blessing for functionality extension: serializer
	$conf_path = bless ($conf_path, 'Project::Easy::Config::File');
	
	make_accessor ($class, 'conf_path', default => $conf_path);
	
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
	
	if ($fixup_core) {
		$fixup_path = IO::Easy->new ($fixup_core)->append ($distro);
	} else {
		$fixup_path = $self->root->append ($self->etc, $distro, $fixup_core);
	}
	
	$fixup_path = $fixup_path->append ($self->id . '.' . $self->conf_format)->as_file;
	
	bless ($fixup_path, 'Project::Easy::Config::File');
}

sub daemon {
	my $core = shift;
	my $code = shift;
	
	return $core->daemons->{$code};
}

sub config {
	my $class = shift;
	
	if (@_ > 0) { # get config for another distro, do not cache
		return $class->conf_package->parse (
			$instance, @_
		);
	}
	
	unless ($instance->{config}) {
		$instance->{config} = $class->conf_package->parse (
			$instance
		);
	}
	
	return $instance->{config};
}

sub db {
	my $class = shift;
	my $type  = shift || '';
	
	my $core = $class->instance; # fetch current process instance
	
	$core->{db}->{$type} = {ts => {}}
		unless $core->{db}->{$type};
	
	my $current_db = $core->{db}->{$type};
	
	unless ($current_db->{$$}) {
		
		$DBI::Easy::ERRHANDLER = sub {
			debug '%%%%%%%%%%%%%%%%%%%%%% DBI ERROR: we relaunch connection %%%%%%%%%%%%%%%%%%%%%%%%';
			return $class->db;
		};
		
		my $t = timer ("database handle start");
		$current_db->{$$} = $class->db_package->new ($core, $type);
		$current_db->{ts}->{$$} = time;
		$t->end;
		
	}
	
	# we reconnect every hour
	if ((time - $current_db->{ts}->{$$}) > 3600) {
		my $old_dbh = delete $current_db->{$$};
		
		$old_dbh->disconnect
			if $old_dbh;
		
		$current_db->{$$} = $class->db_package->new ($core, $type);
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

=item instance

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
