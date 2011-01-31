package Project::Easy::DB;

use Class::Easy;

use DBI;

sub new {
	my $class   = shift;
	my $project = shift;
	my $db_code = shift || 'default';
	
	my $db_conf = $project->config->{db}->{$db_code};
	
	die "db configuration: driver_name must be defined"
		unless defined $db_conf->{driver_name};

	my @connector = ('dbi', $db_conf->{driver_name});
	
	if (exists $db_conf->{attributes}) {
		my %attrs = %{$db_conf->{attributes}};
		push @connector, join ';', map {"$_=$attrs{$_}"} keys %attrs;
	} elsif (exists $db_conf->{dsn_suffix}) {
		die "db configuration: please use 'attributes' hash for setting dsn suffix string";
	}

	my $dsn = join ':', @connector;
	
	die "db configuration: key name 'opts' must be changed to 'options'"
		if exists $db_conf->{opts};
	
	# connect to db
	my $dbh = DBI->connect (
		$dsn,
		$db_conf->{user},
		$db_conf->{pass},
		$db_conf->{options},
	);
	
	if ($dbh and defined $db_conf->{do_after_connect}) {
		my $sql_list = $db_conf->{do_after_connect};
		if (! ref $sql_list) {
			$sql_list = [$sql_list];
		}

		foreach my $sql (@$sql_list) {
			$dbh->do ($sql) or die "can't do $sql";
		}
	}

	# $dbh->trace (1, join ('/', $auction->root, 'var', 'log', 'dbi_trace'));
	
	return $dbh;
}

sub entity {
	my $self = shift;
	my $name = shift;
	
	my ($qname, $table_name, $db_prefix) = @_;
	
	my $entity_name  = $self->entity_prefix . $db_prefix . 'Record';
	my $package_name = $self->entity_prefix . $qname;
	
	return $package_name
	if try_to_use_quiet ($package_name);
	
	die "package $package_name compilation failed with error: $@"
	unless $!;
	
	my $prefix = substr ($self->entity_prefix, 0, -2);
	
	debug "virtual entity creation (prefix => $prefix, entity => $entity_name, table => $table_name, package => $package_name)";
	
	DBI::Easy::Helper->r (
		$qname,
		prefix     => $prefix,
		entity     => $entity_name,
		table_name => $table_name,
	);
}

sub collection {
	my $self = shift;
	my $name = shift;
	
	# we must initialize entity prior to collection
	#$self->entity ($name);
	my $entity_package = $self->entity ($name);
	
	my ($qname, $table_name, $db_prefix) = @_;
	
	my $entity_name  = $self->entity_prefix . $db_prefix . 'Collection';
	my $package_name = $self->entity_prefix . $qname . '::Collection';
	
	return $package_name
		if try_to_use_quiet ($package_name);
	
	die "package $package_name compilation failed with error: $@"
		unless $!;
	
	my $prefix = substr ($self->entity_prefix, 0, -2);
	
	$table_name = $entity_package->table_name
		if $entity_package->can ('table_name');
	
	debug "virtual collection creation (prefix => $prefix, entity => $entity_name, table => $table_name, package => $package_name)";
	
	my @params = (
		$qname,
		prefix      => $prefix,
		entity      => $entity_name,
		table_name => $table_name,
	);
	
	push @params, (column_prefix => $entity_package->column_prefix)
		if $entity_package->can ('column_prefix');
	
	DBI::Easy::Helper->c (@params);
}


1;
