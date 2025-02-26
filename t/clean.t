#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
# use Test::More tests => 1;
use Test::More 'no_plan';
use App::Sqitch;
use Locale::TextDomain qw(App-Sqitch);
# use Test::NoWarnings;
use Test::Exception;
use Test::Warn;
use Test::MockModule;
use Path::Class;
use lib 't/lib';
# use MockOutput;
use TestConfig;

my $CLASS = 'App::Sqitch::Command::clean';
require_ok $CLASS;

my $config = TestConfig->new(
    'core.engine'  => 'sqlite',
    'core.top_dir' => 'test-clean',
);
ok my $sqitch = App::Sqitch->new( config => $config ), 
    'Load a Sqitch object';

isa_ok my $clean = App::Sqitch::Command->load({
    sqitch => $sqitch,
    command => 'clean',
    config => $config,
}), $CLASS, 'clean command';

can_ok $clean, qw(
    project
    target
    target_name
    execute
    _remove_scripts
);

is_deeply [ $CLASS->options ], [qw(
    project=s
    target|t=s
)], 'Options should be correct';

warning_is {
    Getopt::Long::Configure(qw(bundling pass_through));
    ok Getopt::Long::GetOptionsFromArray(
        [], {}, App::Sqitch->_core_opts, $CLASS->options,
    ), 'Should parse options';
} undef, 'Options should not conflict with core options';

my $engine_mocker = Test::MockModule->new('App::Sqitch::Engine::sqlite');
my @projs;
$engine_mocker->mock( registered_projects => sub { @projs });
my $initialized;
$engine_mocker->mock( initialized => sub {
    diag "Gonna return $initialized" if $ENV{RELEASE_TESTING};
    $initialized;
} );

my $mock_target = Test::MockModule->new('App::Sqitch::Target');
my ($target, $orig_new);
$mock_target->mock(new => sub { $target = shift->$orig_new(@_); });
$orig_new = $mock_target->original('new');

# Start with uninitialized database.
$initialized = 0;

##############################################################################
# Test project.
$clean->target($clean->default_target);
throws_ok { $clean->project } 'App::Sqitch::X',
    'Should have error for uninitialized database';
is $@->ident, 'clean', 'Uninitialized database error ident should be "clean"';
is $@->message, __(
    'Database not initialized for Sqitch'
), 'Uninitialized database error message should be correct';

# Specify a project.
isa_ok $clean = $CLASS->new(
    sqitch  => $sqitch,
    project => 'foo',
), $CLASS, 'new clean command';
is $clean->project, 'foo', 'Should have project "foo"';

# Look up the project in the database.
ok $sqitch = App::Sqitch->new( config => $config),
    'Load a sqitch object with SQLite';

ok $clean = $CLASS->new(sqitch => $sqitch), 'Create another clean command';
$clean->target($clean->default_target);
throws_ok { $clean->project } 'App::Sqitch::X',
    'Should get an error for uninitialized db';
is $@->ident, 'clean', 'Uninitialized db error ident should be "clean"';
is $@->message, __ 'Database not initialized for Sqitch',
    'Uninitialized db error message should be correct';

# Try no registered projects.
$initialized = 1;
throws_ok { $clean->project } 'App::Sqitch::X',
    'Should get an error for no registered projects';
is $@->ident, 'clean', 'No projects error ident should be "clean"';
is $@->message, __ 'No projects registered',
    'No projects error message should be correct';

# Try too many registered projects.
@projs = qw(foo bar);
throws_ok { $clean->project } 'App::Sqitch::X',
    'Should get an error for too many projects';
is $@->ident, 'clean', 'Too many projects error ident should be "clean"';
is $@->message, __x(
    'Use --project to select which project to query: {projects}',
    projects => join __ ', ', @projs,
), 'Too many projects error message should be correct';

# Go for one project.
@projs = ('clean');
is $clean->project, 'clean', 'Should find single project';
$engine_mocker->unmock_all;

# Fall back on plan project name.
ok $sqitch = App::Sqitch->new(config => TestConfig->new(
    'core.top_dir' => dir(qw(t sql))->stringify,
)), 'Load a sqitch object with top dir';

isa_ok $clean = $CLASS->new( sqitch => $sqitch ), $CLASS,
    'Another clean command';
$clean->target($clean->default_target);
is $clean->project, $target->plan->project, 'Should have plan project';

##############################################################################
# Test database.
is $clean->target_name, undef, 'Default target should be undef';
isa_ok $clean = $CLASS->new(
    sqitch      => $sqitch,
    target_name => 'foo',
), $CLASS, 'new status with target';
is $clean->target_name, 'foo', 'Should have target "foo"';

##############################################################################
# Test execute().
# Warn on multiple targets
# An empty plan means nothing to clean.
# Cannot find current change in plan
# No changes to clean
# No changes deployed: clean everything
# Changes deployed, one change to clean
# Changes deployed, three changes to clean
