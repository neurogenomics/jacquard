# Validation and benchmarking

Passing a workflow test establishes that the program ran and met its assertions. It does not establish that a corrected cell barcode, target assignment, UMI count or deduplicated insertion is biologically correct. Evaluate those outcomes separately before changing defaults.

## Developer checks

Clone with `--recurse-submodules`, or run `git submodule update --init external/carmack` after checkout. The chemistry adapter tests import the pinned submodule directly. Use Python 3.14 and the committed lockfile:

```bash
uv sync --frozen --group test
uv run --frozen --group test pytest -q
just nf-test
```

The Python suite validates package installation, malformed input handling, barcode resynchronisation, QNAME-to-tag conversion and chemistry-derived adapter sequences. The separate Python CI job runs it even when nf-test's changed-file selection would select no workflow tests. `just nf-test` additionally requires Nextflow, nf-test and Docker and checks the carmack image against the submodule pin.

`-profile test` uses the committed SK609 subset and a chr21 reference. It is an integration fixture, not a representative biological benchmark. `-profile test_full` is a placeholder and deliberately fails until a suitable full-depth dataset is published. Do not describe its registration as full-depth coverage.

## Benchmark tiers

| Tier                | Input and truth                                                                                                   | Required checks                                                                                                                                 |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Contract            | Tiny synthetic paired FASTQs/BAMs, declared original molecule, cell, target, orientation and UMI for every record | Exact accounting; mate/cell consistency; no cell reassignment after filtering; malformed inputs fail                                            |
| Error recovery      | Known sequences with sampled substitutions, indels, Ns, truncation, anchor G-runs and sequencing quality          | Barcode and target precision/recall by error class; false target assignment among true RNA reads; exact molecular dedup precision/recall        |
| Real integration    | Immutable, checksum-identified subsets of multiple independent libraries and chemistries                          | Paired read retention, mapping, feature matrices and tag invariants; no unexplained change from the frozen baseline                             |
| Biological validity | Held-out donors, batches, positive/negative targets, independent assay or species-mixing truth                    | Cell and target specificity, ambient/background contamination, doublets, pseudobulk concordance and reproducible peaks once peak calling exists |
| Scale               | The same real subsets at increasing depth and thread counts, with fixed hardware/storage                          | Wall time, CPU time, peak RSS, read/write bytes, scratch/output bytes, pairs per second, failure/retry rate and cost                            |

The synthetic generator should be independent of the extraction code. Record its seed and truth manifest; do not derive expected answers by executing the algorithm under test. Split training/tuning and held-out evaluation by library or donor, not randomly by reads from the same library.

## Run manifest and comparison

Record the jacquard SHA, carmack SHA and container digest, Nextflow/Java version, complete parameters, external config SHA, FASTQ/reference/annotation checksums, thread and memory requests, executor, CPU architecture, storage type, seed and input read-pair counts. Preserve the Nextflow trace and command scripts. Compare first runs separately from `-resume` cache hits. Fetch and index references before timing the alignment experiment, or report those stages separately.

Use at least three measured repeats after setup and report median and spread. Give throughput per original read pair and per retained pair; a change that silently discards reads can appear faster. Measure peak RSS on the actual scheduler/container rather than treating requested memory as consumption. Keep a canonical biological-output comparison alongside timings: decompress FASTQs, compare records/tags/count matrices, and account for stochastic tie-breaking and gzip headers before treating a binary checksum as a biological difference.

## Experiments to prioritise

1. Compare barcode extraction's full and `--carmack_fast` modes on the same truth sets, stratifying reads that the alignment fallback alone recovers. Require an agreed precision floor before optimising throughput.
2. Benchmark 1, 2, 4, 8, 16 and more threads only where hardware permits. Include compression CPU use, per-worker memory and I/O; stop increasing cores when cost per million correctly assigned pairs rises without a useful latency gain.
3. Compare adapter/overlap trimming and R1 minimum lengths on held-out libraries. Score retained correct molecules and false mappings, not alignment percentage alone.
4. Compare STAR feature and UMI-dedup modes on split-pool and pseudobulk material separately. Freeze the branch-specific matrix file contract: some configurations produce several named matrices instead of `raw/matrix.mtx.gz`. More counted UMIs is not evidence of better recovery without truth.
5. Compare scTIP UMI deduplication with and without linear deduplication using known amplified molecules and genuine independent insertions sharing a coordinate. Quantify both duplicate removal and over-collapse at high occupancy.

Require every contract test to pass. Set numerical quality non-inferiority margins and a practically useful performance gain before running the held-out comparison; do not tune margins after viewing the result. Publish failed and neutral experiments with the winning configuration so later default changes have a reproducible basis.
