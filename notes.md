# Add `sqitch clean` and `sqitch reset` commands

`sqitch clean` checks the database for undeployed changes and removes all related files and plan entries.

`sqitch reset` is a combination of `sqitch revert` and `sqitch clean`.

These commands are meant to be used in development mode.

## Use-cases

List the use-cases to see if there's a need for edge-cases or if we can use one unified implementation.

### Changes at the end

The simplest use-case is: we've added a change - or more than one - at the end of the plan but don't need it anymore.

Steps to implement:

1. Fetch the database state with `$engine->current_state( $self->project )`(see `status.pm` line 123).
2. Compare with the plan, see `emit_status`.
3. Remove undeployed files and plan entries starting at the end.

### Edge-cases

You want to remove a change that is not at the end of the plan file. Eg sqitch.plan

```
change A
change B
change C
```

where you want to get rid of B but keep C. Since sqitch is incremental this might be something we don't want to support. 

- As a workaround the user can sqitch reset to change A and then recover change C files through source control. 
- Or we could support this behaviour through an exclude flag, see below in Options.

## Options

Checking out the git docs (https://git-scm.com/docs/git-clean), these flags could be useful:

- dry-run: just show what would be done.
- exclude: pattern for changes to be ignored.

## First version

In a first version we'll 

- only implement `git clean`
- for the happy path of removing undeployed changes that were added at the end of the plan file
- with no extra options

## Future improvements

- Add the command `git reset` as a combination of `git revert` and `git clean`.
- Add a flag `dry-run` to only show what would be done.
- Add a flag `exclude` to specify which changes you want to keep.

## Implementation