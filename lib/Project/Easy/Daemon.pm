package Project::Easy::Daemon;

use Class::Easy;
use IO::Easy;

has 'pid_file';
has 'code';

sub new {
	my $class    = shift;
	my $singleton = shift;
	my $code     = shift;
	my $config   = shift;
	
	my $root = $singleton->root;
	my $id   = $singleton->id;
	
	if (defined $config->{pid_file}) {
		$config->{pid_file} = file ($config->{pid_file});
	} else {
		
		$config->{pid_file} = $root->file_io ('var', 'run', $id . '-' . $code . '.pid');
	}
	
	if (defined $config->{log_file}) {
		$config->{log_file} = file ($config->{log_file});
	} else {
		$config->{log_file} = $root->file_io ('var', 'log', $id . '-' . $code . '_log');
	}
	
	$config->{code} = $code;
	
	bless $config, $class;
}

sub launch {
	my $self = shift;
	
	if ($self->{package}) {
	
		my $ppid = fork();

		if (not defined $ppid) {
			print "resources not avilable.\n";
		} elsif ($ppid == 0) {
			# exit(0);
			die "cannot detach from controlling terminal"
				if POSIX::setsid() < 0;

			my $log_fh;

			my $pid_file = $self->{pid_file};
			$pid_file->store ($$);
			
			die 'cannot open log file to append'
				unless open $log_fh, '>>', $self->{log_file}->path;

			# DIRTY
			$SIG{__WARN__} = sub {
				print $log_fh @_;
			};
			$SIG{__DIE__} = sub {
				print $log_fh @_;
			};

			my $previous_default = select ($log_fh);
			$|++;
			select ($previous_default);

			close STDOUT;
			close STDERR;
			close STDIN;
			
			if ($self->can ('_launched')) {
				$self->_launched;
			}

		} else {
			exit (0);
		}
	
	} elsif ($self->{bin}) {
		# DEPRECATED
		my $conf_file = $self->{conf_file};
		my $httpd_bin = $self->{bin};
		print "starting daemon by: $httpd_bin -f $conf_file\n";
		`$httpd_bin -f $conf_file`;
		
	}
	
	
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

	print "kill with force\n";

	kill 9, $pid;
	
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