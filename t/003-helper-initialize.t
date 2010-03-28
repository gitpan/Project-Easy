#!/usr/bin/perl

use Class::Easy;

BEGIN {
	use Class::Easy;
	$Class::Easy::DEBUG = 'immediately';
	use IO::Easy;
	unshift @INC, dir->current->dir_io('lib')->path;

	use Test::More qw(no_plan);

	use_ok 'Project::Easy::Helper';

}

use Time::Piece;

my $pack = 'Acme::Project::Easy::Test';
my $path = 'Acme/Project/Easy/Test.pm';

my $here = dir->current;

my $project_root = $here->dir_io ('project-root');

if (-d $project_root) {
	$project_root->rm_tree;
}

# SIMULATION: mkdir project-root;

$project_root->create;

# SIMULATION: cd project-root

my $lib = dir->current->dir_io('lib')->path;

chdir $project_root;

`$^X -I$lib -MProject::Easy::Helper -e initialize $pack`;

# SIMULATION: project-easy $pack

# ::initialize ($pack);

# TEST

my $root = dir->current;
ok (-f $root->append ('lib', $path), 'libraries available');

# SIMULATION: bin/status

ok `$^X -I$lib bin/status` =~ /SUCCESS/ms;

# ok (Project::Easy::Helper::status);

# SIMULATION: bin/config

my $date = localtime->ymd;

my $schema_file = IO::Easy::File->new ('share/sql/default.sql');
$schema_file->parent->create;
$schema_file->store (
	$schema_file->contents .
	"--- $date.15\ncreate table list (list_id integer primary key, list_title text, list_meta text);\n"
	
);

my $update_status = `$^X -I$lib bin/updatedb`;
ok $update_status =~ /done$/ms;

# Project::Easy::Helper::update_schema;

chdir $here;

ok `$^X -I$lib project-root/bin/status` =~ /SUCCESS/ms;

$project_root->rm_tree;

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

$project_root->rm_tree;
