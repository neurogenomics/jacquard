---
name: nf-test-snapshot-blank-lines
type: gotcha
---

# Never snapshot a list of lines that can contain a blank

`snapshot(file.readLines())` on a file with blank lines pulls **unrelated directory listings** into
the snapshot: nf-test resolves a bare `''` entry as a path, and an empty path resolves to the
current directory, whose contents are then serialised. Observed while snapshotting carmack's
`*_stats.txt` — the snapshot came back carrying a listing of `.claude/knowledge/*.md`.

Join before snapshotting:

```groovy
snapshot(file(...).readLines().findAll { !it.startsWith('# Report generated at:') }.join('\n'))
```

Carmack's stats reports also carry a `# Report generated at: <UTC timestamp>` line that must be
filtered, and a `# Carmack version: 0.0.0+<hash>` line that is deliberately kept — so **every
carmack snapshot needs regenerating whenever the submodule is bumped**.
