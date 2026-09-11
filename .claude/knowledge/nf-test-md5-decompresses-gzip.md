---
name: nf-test-md5-decompresses-gzip
type: gotcha
---
# `path(x).md5` in nf-test hashes *decompressed* content

nf-test transparently decompresses a gzip before hashing, so two byte-different but
content-identical `.fastq.gz` files return the **same** md5. Re-gzipping a fixture at a different
compression level to make a "different file" therefore produces two indistinguishable hashes.

Consequence: an assertion phrased as "byte-identical" is really testing *content*-identity. Where
the byte-level claim matters (e.g. proving the raw samplesheet R2 reached `prepare-reads`
untouched), hash the raw bytes instead:

```groovy
java.security.MessageDigest.getInstance('MD5').digest(new File(p).bytes).encodeHex().toString()
```

To build a genuinely different FASTQ fixture, take a different number of records — not a different
compression level.

Two more nf-test Groovy traps, both hit inside a `workflow {}` block in a `.nf.test`:
- `writer.writeLine(...)` fails with `Missing process or function writeLine(...)` — use `<<`.
- A literal `\n` is consumed by nf-test's own GString interpolation before Nextflow sees it — write
  `\\n` or avoid it.
