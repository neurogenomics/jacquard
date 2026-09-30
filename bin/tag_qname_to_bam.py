#!/usr/bin/env python3
"""Move carmack's pipe-delimited scTIP QNAME fields into proper BAM tags.

carmack writes scTIP read names as `readid|CB=<barcode>|UR=<umi>` so the barcode and the UMI
survive as a SAM QNAME, which is truncated at the first whitespace. Downstream tools read tags,
not names, so the fields are lifted out here and the QNAME is restored to the bare read id.

Self-contained on purpose: it runs inside the carmack container, which has pysam but not this
repository's `core` package.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pysam

# The QNAME spells the UMI `UR` — the raw, uncorrected UMI — while the BAM tag for it is `UB`.
QNAME_TAGS = {"CB": "CB", "UR": "UB"}


def qname_tags(qname: str) -> tuple[str, dict[str, str]]:
    """Split a carmack QNAME into its bare read id and the BAM tags its fields carry."""
    read_id, *fields = qname.split("|")
    tags = {}
    for field in fields:
        key, separator, value = field.partition("=")
        if separator and key in QNAME_TAGS:
            tags[QNAME_TAGS[key]] = value
    missing = [key for key, tag in QNAME_TAGS.items() if not tags.get(tag)]
    if missing:
        raise ValueError(f"Read '{qname}' carries no {' or '.join(f'{key}=' for key in missing)} field in its QNAME.")
    return read_id, tags


def retag_bam(source: Path, destination: Path, threads: int = 1) -> int:
    """Rewrite every record of `source` into `destination`, returning the number written."""
    written = 0
    with (
        pysam.AlignmentFile(str(source), threads=threads) as reader,
        pysam.AlignmentFile(str(destination), "wb", template=reader, threads=threads) as writer,
    ):
        for record in reader:
            read_id, tags = qname_tags(record.query_name)
            record.query_name = read_id
            for tag, value in tags.items():
                record.set_tag(tag, value, value_type="Z")
            writer.write(record)
            written += 1
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--threads", type=int, default=1)
    args = parser.parse_args(argv)

    try:
        retag_bam(args.input, args.output, args.threads)
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
