#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
# use Test::More tests => 1;
use Test::More 'no_plan';
use App::Sqitch;
use Test::Warn;

use lib 't/lib';
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

##############
# Test cases #
##############
# Warn on multiple targets
# An empty plan means nothing to clean.
# Cannot find current change in plan
# No changes to clean
# No changes deployed: clean everything
# Changes deployed, one change to clean
# Changes deployed, three changes to clean
