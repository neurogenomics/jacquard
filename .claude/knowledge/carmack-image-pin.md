---
name: carmack-image-pin
type: gotcha
---

# The carmack image tag and the submodule pin move together

Every carmack-derived module declares `ghcr.io/neurogenomics/carmack:sha-<7>`, where `<7>` is the
short sha of the `external/carmack` gitlink. carmack's publish workflow pushes `sha-<7>` for each
commit that passes its tests on `main`, and never moves it, so the tag and the pin name the same
commit. Nothing is built locally.

They have to be kept in step by hand, because nothing ties a `container` string to a gitlink.
If they drift, the symptom is misleading: every carmack stats file opens with
`# Carmack version: 0.0.0+<sha>`, and the snapshots hold the pin's sha. So a module left on an
old tag fails its snapshots with a version diff that looks like a carmack regression.

`just carmack-image` (which `just nf-test` and `just smoke` depend on) and the nf-test CI action
both check that every `ghcr.io/neurogenomics/carmack:` reference under `modules/` and `conf/`
is exactly `sha-<pin>`, and name the offending tags when it is not.

## Bumping

1. Move the submodule to the tip of carmack's `main` and stage it:
   ```bash
   git -C external/carmack fetch origin main
   git -C external/carmack checkout origin/main
   git add external/carmack
   ```
   The justfile reads the pin from the index (`git ls-files -s external/carmack`), so an unstaged
   checkout doesn't count yet.
2. Wait for carmack's "Publish image" run for that commit to finish. Until then `sha-<7>` doesn't
   exist, and `just carmack-image` fails at the pull.
3. Replace the tag in every carmack `container` directive (seven modules today), so it names the new
   `sha-<7>`.
4. Refresh the snapshots. Grep for the old short sha afterwards, outside `.git` and `external`; it
   should appear nowhere.

A carmack commit that isn't on `main` has no published image. To try one, build it locally under
a tag of your own, and don't commit the modules pointing at it.
