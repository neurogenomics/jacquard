---
name: carmack-image-tag-is-global
type: gotcha
---

# `carmack:local` is one mutable tag shared by every worktree

`ghcr.io/crick-pipelines-stp/carmack:local` is a tag in the **host Docker daemon**, not something
scoped to a checkout. Every worktree that runs `just nf-test` or `just smoke` first runs the
`carmack-image` recipe, which rebuilds that same tag from _its own_ `external/carmack` pin:

```
CARMACK_IMAGE := "ghcr.io/crick-pipelines-stp/carmack:local"
carmack-image:
    git submodule update --init external/carmack
    docker build -t {{CARMACK_IMAGE}}-base --build-arg CARMACK_VERSION=0.0.0+$(...) external/carmack
```

Two worktrees on different carmack pins therefore **silently clobber each other**. The second
build wins, and the first run carries on against the wrong binary — nothing warns, because the
tag still resolves. It surfaces later as snapshot diffs on the `# Carmack version: 0.0.0+<sha>`
header that every carmack stats file carries, which is the only place the swap is visible.

This is not hypothetical: on 2026-09-17 a `just nf-test` in the main checkout (pinned `fe755ee`)
overwrote the `ffa5349` image that a concurrent run in `.worktrees/17-anchor-run-linegraph` was
using, invalidating an hour of that run.

**Before invoking any `just` recipe that builds the image, check nothing else is using it:**

```bash
pgrep -af 'nf-test|nextflow'
docker run --rm --entrypoint /bin/bash ghcr.io/crick-pipelines-stp/carmack:local \
    -c 'pip show carmack | grep Version'   # which pin currently owns the tag
```

Also note `pkill -f nextflow` matches its own command line and will kill the invoking shell; it
will also kill unrelated worktrees' runs. Kill a specific `just nf-test` by PID instead.

## A working-tree-only submodule bump is silently reverted

`carmack-image` starts with `git submodule update --init external/carmack`, which resets the
submodule to the commit recorded in the **index**. So checking out a new carmack revision without
`git add external/carmack` does nothing: the recipe puts it back and builds the _old_ pin, while
`git status` still shows ` M external/carmack` as though the bump took. Stage the gitlink first:

```bash
git -C external/carmack checkout <new-sha>
git add external/carmack          # ← without this the next `just` recipe reverts it
```

Always confirm what actually got built before trusting regenerated snapshots:

```bash
docker run --rm --entrypoint /bin/bash ghcr.io/crick-pipelines-stp/carmack:local \
    -c 'pip show carmack | grep Version'
```

The structural fix — embedding the submodule SHA in the tag so each pin gets its own image — is
not done; see [[carmack-container-needs-procps]] for the other half of how this image is built.
