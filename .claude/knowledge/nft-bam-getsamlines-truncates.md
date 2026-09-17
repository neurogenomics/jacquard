---
name: nft-bam-getsamlines-truncates
type: gotcha
---

# `getSamLines()` can return a partial record set under nf-test

Observed with `nft-bam@0.5.0` on a paired BAM: `getSamLines()` returned **13 332 of 26 664**
records under nf-test, while driving the same jar directly from Java returned all 26 664. Cause not
established.

So **never write a record-count assertion over a BAM** read this way — `size()` may silently be
half the truth, and the test will pass or fail for reasons unrelated to the code.

Assertions that survive the truncation:

- **Set equality over distinct values.** `qnames.toUnique().toSorted() == fastq_headers.toSorted()`
  is safe: if the returned set were the first half of a mate-adjacent BAM, the distinct count would
  halve and the equality would fail. It cannot pass on truncated input.
- **Counts read from the tool's own log** rather than from the BAM — e.g. bowtie2's
  `13332 reads` / `13332 (100.00%) were paired`, or umi_tools' input/output counts.

Related trap in the same tests: Groovy's `List.unique()` and `List.sort()` **mutate the receiver**,
so an assertion that uniques a list changes what a later assertion in the same `assertAll` block
measures. Use `toUnique()` / `toSorted()`.
