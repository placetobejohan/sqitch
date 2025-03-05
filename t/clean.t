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
#use MockOutput;
use TestConfig;
use Capture::Tiny 0.12 ':all';

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
), $CLASS, 'new clean with target';
is $clean->target_name, 'foo', 'Should have target "foo"';

##############################################################################
# Test execute().

# TEST CASE 1: empty plan
# Add project 
@projs = ('clean');

# Set plan file
sub create_clean_command {
    my $file = shift;
    $config->update('core.plan_file' => $file->stringify);
    my $sqitch = App::Sqitch->new(config => $config);
    return App::Sqitch::Command::clean->new(
        sqitch  => $sqitch,
    );
}
my $file = file qw(t plans), "clean-empty.plan";
my $clean = create_clean_command($file);

# An empty plan means nothing to clean.
throws_ok { $clean->execute } 'App::Sqitch::X',
    'Should get an error for an empty plan';
is $@->ident, 'clean', 'Empty plan error ident should be "clean"';
is $@->message, __ 'Nothing to clean: plan is empty',
    'Empty plan error message should be correct';

# TEST CASE 2: Cannot find current change in plan
# Set plan file
my $file = file qw(t plans), "clean-multi.plan";
my $clean = create_clean_command($file);

# Add a change to the state that doesn't exist in the plan.
my $dt = App::Sqitch::DateTime->new(
    year       => 2012,
    month      => 7,
    day        => 7,
    hour       => 16,
    minute     => 12,
    second     => 47,
    time_zone => 'America/Denver',
);
my $state = {
    project         => 'clean',
    change_id       => 'someid',
    change          => 'widgets_table',
    committer_name  => 'fred',
    committer_email => 'fred@example.com',
    committed_at    => $dt->clone,
    tags            => [],
    planner_name    => 'barney',
    planner_email   => 'barney@example.com',
    planned_at      => $dt->clone->subtract(days => 2),
};
$engine_mocker->mock( current_state => $state );

throws_ok { $clean->execute } 'App::Sqitch::X',
    'Should get an error for missing current change';
is $@->ident, 'clean', 'Missing current change error ident should be "clean"';
is $@->message, __ 'Make sure you are connected to the proper database for this project.',
    'Missing current change error message should be correct';

# TEST CASE 3: No changes to clean (non-empty plan)
# Plan file can stay the same (clean-multi.plan)

# Get current state based on the plan file and the number of undeployed changes
sub get_current_state {
    my ($clean, $undeployed_changes) = @_;
    $undeployed_changes //= 0;

    my $plan = $clean->default_target->plan;
    my @changes;

    while (my $change = $plan->next) {
        push @changes, $change;
    }

    my $last_change_index = @changes - $undeployed_changes - 1;
    my $last_change = $changes[$last_change_index];

    return {
        project         => $plan->project,
        change_id       => $last_change->id,
        change          => $last_change->name,
        committer_name  => 'fred',
        committer_email => 'fred@example.com',
        committed_at    => App::Sqitch::DateTime->now,
        tags            => [],
        planner_name    => $last_change->planner_name,
        planner_email   => $last_change->planner_email,
        planned_at      => $last_change->timestamp,
    };
}

# Set current state: no undeployed changes
my $state = get_current_state($clean, 0);
$engine_mocker->mock(current_state => sub { return $state });

# Execute should return a message saying there are no changes to clean
my $output = capture_stdout { $clean->execute };
like($output, qr/Nothing to clean: all changes deployed\.\n/, 'No undeployed changes should print "Nothing to clean: all changes deployed"');

# No changes deployed: clean everything
# Changes deployed, one change to clean
# Changes deployed, three changes to clean
