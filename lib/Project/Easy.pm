package Project::Easy;

# $Id: Easy.pm,v 1.6 2009/07/07 19:46:54 apla Exp $

use Class::Easy;
use IO::Easy;

use vars qw($VERSION);

$VERSION = '0.04';

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
		use Project::Easy::Helper;
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
	my $distro = $distro_path->as_file->contents;
	
	chomp $distro;
	
	die "can't recognise distribution '$distro'"
		unless $distro;
	
	make_accessor ($class, 'distro', default => $distro);
	
	my $conf_path = $root->append ($class->etc, $class->id . '.' . $class->conf_format);
	
	die "can't locate generic config file at '$conf_path'"
		unless -f $conf_path;
	
	make_accessor ($class, 'conf_path', default => $conf_path);
	
	my $fixup_path = $root->append ($class->etc, $distro, $class->id . '.' . $class->conf_format);
	
	die "can't locate fixup config file at '$fixup_path'"
		unless -f $fixup_path;
	
	make_accessor ($class, 'fixup_path', default => $fixup_path);
	
}

sub fixup_path_distro {
	my $self   = shift;
	my $distro = shift || $self->distro;
	
	$self->root->append ($self->etc, $distro, $self->id . '.' . $self->conf_format)
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

=head1 METHODS

=head2 new

TODO

=cut

=head1 AUTHOR

Ivan Baktsheev, C<< <apla at the-singlers.us> >>

=head1 BUGS

Please report any bugs or feature requests to my email address,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBI-Easy>. 
I will be notified, and then you'll automatically be notified
of progress on your bug as I make changes.

=head1 SUPPORT



=head1 ACKNOWLEDGEMENTS



=head1 COPYRIGHT & LICENSE

Copyright 2007-2009 Ivan Baktsheev

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut
