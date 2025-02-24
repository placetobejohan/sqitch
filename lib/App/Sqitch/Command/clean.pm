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
    
    # If the state is empty all changes can be removed, set index to -1
    my $current_index = -1;
    if(not defined $state) {
        $self->info(__ 'No changes deployed.');
    } else {
        $current_index = $plan->index_of( $state->{change_id} ) // do {
            $self->vent(__x(
                'Cannot find the current change in {file}.',
                file => $self->plan_file
            ));
            hurl clean => __ 'Make sure you are connected to the proper '
                        . 'database for this project.';
        };
        $self->info(__x(
            'Deployed change: {change}',
            change => $state->{change},
        ));
    }

    # Check if there are changes to clean
    # All changes in the plan with an index greater than the current one can be removed
    my $removal_count = $plan->count - ($current_index + 1);
    if($removal_count == 0) {
        $self->info(__ 'No changes to clean.');
        return;
    }

    $self->info(__n(
        "Change to be removed: $removal_count",
        "Changes to be removed: $removal_count",
        $removal_count
    ));

    # Remove drv scripts for each change
    for my $i ($current_index + 1..$plan->count-1) {
        my $change = $plan->change_at($i);
        $self->_remove_scripts($change);
    }

    # Update the plan
    $plan->write_to( $self->plan_file, undef, $state->{change_id});
}

# Remove script files if they exist
# TODO: get script files from template config instead of hardcoding drv
sub _remove_scripts {
    my ( $self, $change ) = @_;
    my @files = ($change->deploy_file, $change->revert_file, $change->verify_file);
    $self->info(__x(
        'Removing scripts for change {change}',
        change => $change->format_name,
    ));

    foreach my $file (@files) {
        if (-e $file) {
            unlink $file or hurl clean => __x(
                'Cannot remove {file}: {error}',
                file  => $file,
                error => $!,
            );
        } else {
            $self->warn(__x(
                'Cannot remove {file}: does not exist',
                file => $file
            ));
        }
    }
}

1;

__END__

=head1 Name

App::Sqitch::Command::clean - Remove undeployed changes
