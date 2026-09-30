---
name: carmack-image-main-tag
type: gotcha
---

# The carmack image is `:main`, and the submodule pin has to follow it

Every carmack-derived module declares `ghcr.io/neurogenomics/carmack:main`. carmack's publish
workflow pushes that tag after the tests pass on each push to its `main`, so it moves without
anything in this repo changing. Nothing is built locally any more.

Two things tie the tag back to this repo:

- **Snapshots record a carmack version.** Every carmack stats file opens with
  `# Carmack version: 0.0.0+<sha>`, and the snapshots hold the sha of the `external/carmack`
  pin. When carmack's `main` moves, every carmack snapshot fails at once, though nothing in
  jacquard changed.
- **Docker never re-pulls a tag it already holds.** A machine that pulled `:main` last week keeps
  running last week's carmack until something pulls again.

`just carmack-image` (which `just nf-test` and `just smoke` depend on) and the nf-test CI action
both pull `:main`, read `carmack --version` from it, and stop if the sha differs from the
submodule's gitlink. That turns a moved `main` into one error naming the cause, instead of a page
of snapshot diffs.

When that check fails, bump the pin to carmack's `main` tip and refresh the snapshots:

```bash
git -C external/carmack fetch origin main
git -C external/carmack checkout origin/main
git add external/carmack          # the check reads the index, so stage before re-running
```

The check reads the gitlink from the index (`git ls-files -s external/carmack`), not the
submodule's working tree, so an unstaged checkout still fails it.

A carmack commit that is not on `main` has no published image. To run jacquard against one, build
it under a tag of your own and point the modules at that tag for the session; building it as
`:main` would shadow the published image for every checkout on the machine.
