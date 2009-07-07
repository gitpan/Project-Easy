package Project::Easy::Config;

use Class::Easy;

use JSON;

sub patch ($$);

sub parse {
	my $class  = shift;
	my $core   = shift;
	my $distro = shift;
	
	my $path  = $core->conf_path;
	my $fixup = $core->fixup_path_distro ($distro);
	
	my $parser = JSON->new;
	$parser->utf8 (1);
	
	my $conf = $path->as_file->contents;
	my $alt  = $fixup->as_file->contents;
	
	# here we want to expand some generic params
	my $expand = {
		root => $core->root->path,
		id   => $core->id,
		distro => $core->distro,
	};
	
	foreach (keys %$expand) {
		$conf =~ s/\{\$$_\}/$expand->{$_}/sg;
		$alt  =~ s/\{\$$_\}/$expand->{$_}/sg;
	}
	
	my $data     = $parser->decode ($conf);
	my $data_alt = $parser->decode ($alt);
	
	patch ($data, $data_alt);
	
	return $data;
}

sub patch ($$) {
	my $struct    = shift;
	my $patch     = shift;
	      
	return if ref $struct ne 'HASH' and ref $patch ne 'HASH';
	    
	foreach my $k (keys %$patch) {
		if (! exists $struct->{$k}) {
			$struct->{$k} = $patch->{$k};
		} elsif (
			(! ref $patch->{$k} && ! ref $struct->{$k})
			|| (ref $patch->{$k} eq 'ARRAY' && (ref $struct->{$k} eq 'ARRAY'))
			|| (ref $patch->{$k} eq 'Regexp' && (ref $struct->{$k} eq 'Regexp'))
		) {
			$struct->{$k} = $patch->{$k};
		} elsif (ref $patch->{$k} eq 'HASH' && (ref $struct->{$k} eq 'HASH')) {
			patch ($struct->{$k}, $patch->{$k});
		} elsif (ref $patch->{$k} eq 'CODE' && (ref $struct->{$k} eq 'CODE' || ! defined $struct->{$k})) {
			$struct->{$k} = $patch->{$k};
		}
	}
}

1;