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

1;
