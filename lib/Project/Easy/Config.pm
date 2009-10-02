package Project::Easy::Config;

use Class::Easy;

sub patch ($$);

sub parse {
	my $class  = shift;
	my $core   = shift;
	my $distro = shift;
	
	my $path  = $core->conf_path;
	my $fixup = $core->fixup_path_distro ($distro);
	
	# here we want to expand some generic params
	my $expansion = {
		root   => $core->root->path,
		id     => $core->id,
		distro => $core->distro,
	};
	
	my $conf = $path->deserialize ($expansion);
	my $alt  = $fixup->deserialize ($expansion);
	
	patch ($conf, $alt);
	
	return $conf;
}

my $ext_syn = {
	'pl' => 'perl',
	'js' => 'json',
};

sub serializer {
	shift;
	my $type = shift;
	
	$type = $ext_syn->{$type}
		if exists $ext_syn->{$type};
	
	my $pack = "Project::Easy::Config::Format::$type";
	
	die ('no such serializer: ', $type)
		unless try_to_use ($pack);
	
	return $pack->new;
}

sub string_from_template {

    my $template  = shift;
    my $expansion = shift;

    return unless $template;

    foreach (keys %$expansion) {
        next unless defined $expansion->{$_};

        $template =~ s/\{\$$_\}/$expansion->{$_}/sg;
    }

    return $template;
}

sub patch ($$) {
	my $struct    = shift;
	my $patch     = shift;
	      
	return if ref $struct ne 'HASH' and ref $patch ne 'HASH';

    unless ( scalar keys %$struct ) {
        %$struct = %$patch;
        return;
    }
    
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
