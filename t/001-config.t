#!/usr/bin/perl

use utf8; # for real testing how works our Data::Dumper stringification for unicode

use strict;
use warnings;
use Data::Dumper;

use Test::More qw(no_plan);

use_ok qw(Project::Easy::Config);

use_ok qw(Project::Easy::Config::File);

is(Project::Easy::Config::patch('',''), undef, 'Project::Easy::Config::patch N1 (both arguments are empty)');

is(Project::Easy::Config::patch(undef, undef), undef, 'Project::Easy::Config::patch N2 (both arguments are undef)');

is(Project::Easy::Config::patch({}, {}), undef, 'Project::Easy::Config::patch N3 (empty hashrefs as params)');

#####
my ($struct, $patch) = (
    { test1 => 1, test2 => 2 },
    { test2 => 3 }
);

Project::Easy::Config::patch($struct, $patch);
is_deeply($struct,
    {
        test1 => 1,
        test2 => 3,
    },
    'Project::Easy::Config::patch N4 (override param)'
);

#####

($struct, $patch) = (
    { test1 => 1, test2 => 2 },
    { test3 => 'привет' }
);

Project::Easy::Config::patch($struct, $patch);
is_deeply($struct,
    {
        test1 => 1,
        test2 => 2,
        test3 => 'привет',
    },
    'Project::Easy::Config::patch N5 (add param)'
);

#########################################################
# here we test embedded serializers: perl and json
#########################################################

my $serializer_j = Project::Easy::Config->serializer ('json');
ok ($serializer_j);

is_deeply (
	$struct,
	$serializer_j->parse_string ($serializer_j->dump_struct ($struct))
);

my $serializer_p = Project::Easy::Config->serializer ('perl');
ok ($serializer_p);

is_deeply (
	$struct,
	$serializer_p->parse_string ($serializer_p->dump_struct ($struct))
);

#########################################################
# interface to config files
#########################################################

my $file_name = 'aaa.json';

my $config_file = Project::Easy::Config::File->new ($file_name);

$config_file->serialize ({hello => 'world'});

# testing json and adequateness
ok $config_file->contents =~ /"hello"\s*:\s*"world"/s;

$config_file->patch ({hello => '{$world}'});

ok $config_file->contents =~ /"hello"\s*:\s*"{\$world}"/s;

my $deserialized = $config_file->deserialize ({world => 'planet earth'});

ok scalar (keys %$deserialized) == 1;

ok $deserialized->{hello} eq 'planet earth';

unlink $file_name;

# similar, but for perl

$file_name = 'aaa.pl';

$config_file = Project::Easy::Config::File->new ($file_name);

$config_file->serialize ({hello => 'world'});

# testing json and adequateness
ok $config_file->contents =~ /'hello'\s*=>\s*'world'/s;

$config_file->patch ({hello => '{$world}'});

ok $config_file->contents =~ /'hello'\s*=>\s*'{\$world}'/s;

$deserialized = $config_file->deserialize ({world => 'planet earth'});

ok scalar (keys %$deserialized) == 1;

ok $deserialized->{hello} eq 'planet earth';

unlink $file_name;
