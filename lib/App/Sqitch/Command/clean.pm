package App::Sqitch::Command::clean;

use 5.010;
use strict;
use warnings;
use utf8;
use Locale::TextDomain qw(App-Sqitch);
use App::Sqitch::X     qw(hurl);
use Moo;
use App::Sqitch::Types qw(Str Bool Target);
use Try::Tiny;
use namespace::autoclean;

# Temp use to print objects
use Data::Dumper;

extends 'App::Sqitch::Command';

# VERSION

has target_name => (
    is  => 'ro',
    isa => Str,
);

has target => (
    is      => 'rw',
    isa     => Target,
    handles => [qw(engine plan plan_file)],
);

has project => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    default => sub {
        my $self = shift;
        try { $self->plan->project } catch {
            # Just die on parse and I/O errors.
            die $_ if try { $_->ident eq 'parse' || $_->ident eq 'io' };

            # Try to extract a project name from the registry.
            my $engine = $self->engine;
            hurl status => __ 'Database not initialized for Sqitch'
              unless $engine->initialized;
            my @projs = $engine->registered_projects
              or hurl status => __ 'No projects registered';
            hurl status => __x(
                'Use --project to select which project to query: {projects}',
                projects => join __ ', ',
                @projs,
            ) if @projs > 1;
            return $projs[0];
        };
    },
);

sub execute {
    my $self = shift;

    # Connect to the database.
    my ($targets) = $self->parse_args(
        target => $self->target_name,
        args   => \@_,
    );

    # Warn on multiple targets.
    my $target = shift @{$targets};
    $self->warn(
        __x(
            'Too many targets specified; connecting to {target}',
            target => $target->name,
        )
    ) if @{$targets};

    # Good to go.
    $self->target($target);
    my $engine = $target->engine;

    # Where are we?
    $self->comment( __x 'On database {db}', db => $engine->destination );

    # An empty plan means nothing to clean.
    my $plan = $self->plan;
    hurl {
        ident   => 'clean',
        message => __ 'Nothing to clean: plan is empty',
    } unless $plan->count;

    # Fetch state
    my $state = $engine->current_state( $self->project );

    # Watch out! If nothing is deployed $state is undefined (and all changes can be removed)
    # Updating the plan and removing the files should be an atomic operation so we don't end up in an inconsistent state

    # 1. Check if there are changes to clean
    # 2. Update the plan
    # 3. Remove the files

    
}

1;

__END__

=head1 Name

App::Sqitch::Command::clean - Remove undeployed changes
