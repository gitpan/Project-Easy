package Project::Easy::Daemon;

use Class::Easy;

has 'pid_file';
has 'code';

sub new {
	my $class    = shift;
	my $singleton = shift;
	my $code     = shift;
	my $config   = shift;
	
	my $root = $singleton->root;
	my $id   = $singleton->id;
	
	my $pid_file = $root->append ('var', 'run', $id . '-' . $code . '.pid')->as_file;
	
	$config->{code} = $code;
	$config->{pid_file} = $pid_file;
	
	bless $config, $class;
}

sub launch {
	my $self = shift;
	
	my $conf_file = $self->{conf_file};
	my $httpd_bin = $self->{bin};
	print "starting daemon by: $httpd_bin -f $conf_file\n";
	`$httpd_bin -f $conf_file`;
	
	sleep 1;
	
	warn "not running"
		unless $self->running;
}

sub running {
	my $self = shift;
	
	my $pid = $self->pid;
	
	return 0 unless defined $pid;
	
	if ($^O eq 'darwin') {
		my $ps = `ps -x -p $pid -o rss=,command=`;
		if ($ps =~ /^\s+(\d+)\s+(.*)$/m) {
			return 1;
		}
	} else {
		return kill 0, $pid;
	}
}

sub pid {
	my $self = shift;
	
	my $pid;
	if (-f $self->pid_file) {
		$pid = $self->pid_file->contents;
	}
	
	return unless defined $pid;
	
	return unless $pid =~ /(\d+)/;
	
	return $1;
}

sub shutdown {
	my $self = shift;
	
	my $pid = $self->pid;
	
	return 1 unless defined $pid; 
	
	kill 15, $pid;

	my $count = 10;
	
	for (1..$count) {
		print ($count + 1 - $_ ."… ");
		sleep 1;
		# wait one more second
		unless ($self->running) {
			return 1;
		}
	}
	
	return 0;
}

sub process_command {
	my $self = shift;
	my $comm = shift;
	
	if ($comm eq 'stop') {
		if (! $self->running) {
			print "no process is running\n";
			exit;
		}
		
		print "awaiting process to kill… ";
		$self->shutdown;
		
		print "\n";
	
	} elsif ($comm eq 'start') {
		if ($self->running) {
			print "no way, process is running\n";
			exit;
		}
		
		$self->launch;
		
	} elsif ($comm eq 'restart') {
		if ($self->running) {
			my $finished = $self->shutdown;
			
			unless ($finished) {
				print "pid is running after kill, please kill manually\n";
				exit;
			}
		}
		
		$self->launch;
	}
	
}

1;