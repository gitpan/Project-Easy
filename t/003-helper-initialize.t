#!/usr/bin/perl

use Class::Easy;

BEGIN {
	use Class::Easy;
	$Class::Easy::DEBUG = 'immediately';
}

use Test::More qw(no_plan);

use Time::Piece;

use IO::Easy::Dir;

use Project::Easy::Helper;

my $pack = 'Acme::Project::Easy::Test';
my $path = 'Acme/Project/Easy/Test.pm';

my $here = IO::Easy::Dir->current;

if (-d $here->append ('project-root')) {
	`rm -rf project-root`;
}

# SIMULATION: mkdir project-root;

my $dir = IO::Easy::Dir->new ('project-root');
$dir->create;

# SIMULATION: cd project-root

chdir $dir;

`$^X -MProject::Easy::Helper -e initialize $pack`;

# SIMULATION: project-easy $pack

# ::initialize ($pack);

# TEST

my $root = IO::Easy::Dir->current;
ok (-f $root->append ('lib', $path));

# SIMULATION: bin/status

ok `$^X bin/status` =~ /SUCCESS/ms;

# ok (Project::Easy::Helper::status);

# SIMULATION: bin/config

my $date = localtime->ymd;

my $schema_file = IO::Easy::File->new ('share/sql/default.sql');
$schema_file->parent->create;
$schema_file->store (
	$schema_file->contents .
	"--- $date.15\ncreate table list (list_id integer primary key, list_title text, list_meta text);\n"
	
);

my $update_status = `$^X bin/updatedb`;
ok $update_status =~ /done$/ms;

# Project::Easy::Helper::update_schema;

chdir $here;

ok `$^X project-root/bin/status` =~ /SUCCESS/ms;

`rm -rf project-root`;

exit;

my $list = $pack->entity ('list');

ok $list;

warn $list;

my $list_rec = $list->new;

$list_rec->id (15);
$list_rec->title ('hello, world!');

ok $list_rec->create;

ok $pack->collection ('list')->new->count == 1;

# REMOVING var AND REINITIALIZATION

$root->dir_io ('var')->rm_tree;

warn '!!!!!!!!!!!!!!!', Project::Easy::Helper::status;

# RESTORING

chdir $here;

`rm -rf project-root`;
