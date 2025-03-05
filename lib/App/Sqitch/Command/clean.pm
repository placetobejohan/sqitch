package App::Sqitch::Command::clean;

use 5.010;
use strict;
use warnings;
use utf8;
use Locale::TextDomain qw(App-Sqitch);
use App::Sqitch::X qw(hurl);
use Moo;
use App::Sqitch::Types qw(Str Bool Target);
use Try::Tiny;
use namespace::autoclean;

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
            hurl clean => __ 'Database not initialized for Sqitch'
              unless $engine->initialized;
            my @projs = $engine->registered_projects
              or hurl clean => __ 'No projects registered';
            hurl clean => __x(
                'Use --project to select which project to query: {projects}',
                projects => join __ ', ',
                @projs,
            ) if @projs > 1;
            return $projs[0];
        };
    },
);

sub options {
    return qw(
        project=s
        target|t=s
    );
}

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
        $self->info(__ 'Nothing to clean: all changes deployed.');
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

=head1 Synopsis

  my $cmd = App::Sqitch::Command::clean->new(%params);
  $cmd->execute;

=head1 Description

If you want to know how to use the C<clean> command, you probably want to be reading C<sqitch-clean>. But if you really want to know how the C<clean> command works, read on.

=head1 Interface

=head2 Class Methods

=head3 C<options>

  my @opts = App::Sqitch::Command::clean->options;

Returns a list of L<Getopt::Long> option specifications for the command-line
options for the C<clean> command.

=head2 Attributes

=head3 C<target_name>

The name or URI of the database target as specified by the C<--target> option or the configuration file.

=head3 C<target>

An L<App::Sqitch::Target> object from which to retrieve the current state and plan. Must be instantiated by C<execute()>.

=head3 C<project>

The name of the project to clean. Derived from the C<--project> option, plan or the registry.

=head2 Instance Methods

=head3 C<execute>

  $clean->execute;

Executes the clean command. The current state of the target database will be
compared to the plan in order to decide which changes can be removed.

=head3 C<_remove_scripts>

  $clean->_remove_scripts($change);

Removes the deploy, revert, and verify scripts for the given change, both from the plan file and the file system.

=head1 See Also

=over

=item L<sqitch-clean>

Documentation for the C<clean> command to the Sqitch command-line client.

=item L<sqitch>

The Sqitch command-line client.

=back

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 License

Copyright (c) 2012-2025 David E. Wheeler, 2012-2021 iovation Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut
