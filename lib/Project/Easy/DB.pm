package Project::Easy::DB;

use Class::Easy;

use DBI;

sub new {
	my $class   = shift;
	my $project = shift;
	my $db_code = shift;
	
	my $db_conf = $project->config->{"db$db_code"};
	
	my $dsn = $db_conf->{dsn};
	
	if (exists $db_conf->{dsn_suffix}) {
		my $dsn_suffix = $db_conf->{dsn_suffix};
		if (ref $dsn_suffix and ref $dsn_suffix eq 'ARRAY') {
			$dsn = join ';', $dsn, @$dsn_suffix;
		} else {
			$dsn = join ';', $dsn, $dsn_suffix;
		}
	}
	
	# connect to db
	my $dbh = DBI->connect (
		$dsn,
		$db_conf->{user},
		$db_conf->{pass},
		$db_conf->{opts},
	);
	
	# $dbh->trace (1, join ('/', $auction->root, 'var', 'log', 'dbi_trace'));
	
	return $dbh;
}

1;