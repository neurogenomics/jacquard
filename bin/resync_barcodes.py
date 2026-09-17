#!/usr/bin/env python3
"""Resync carmack's synthesized barcode read against a trimmed scRNA cDNA read.

STARsolo pairs its two input FASTQs positionally, record for record, so a trimmer that drops a
cDNA read without dropping the matching barcode read shifts every later pair by one and assigns
the rest of the library to the wrong cells. fastp cannot carry the barcode read through the trim —
it is a third file, not a mate — so the surviving read ids are replayed onto it here.

Self-contained on purpose: it runs inside a bare python container, which has the standard library
but not this repository's `core` package.
"""

from __future__ import annotations

import argparse
import gzip
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import BinaryIO


def read_id(header: bytes) -> bytes:
    """The read a FASTQ header names, without its comment or its mate suffix.

    Trimming may rewrite either, so neither can be part of the identity two streams are paired on.
    """
    fields = header[1:].split()
    if not fields:
        raise ValueError(f"FASTQ header {header!r} names no read.")
    name = fields[0]
    return name[:-2] if name.endswith((b"/1", b"/2")) else name


def fastq_records(handle: BinaryIO) -> Iterator[tuple[bytes, bytes]]:
    """Yield each record as its read id and the four lines exactly as they were read."""
    while header := handle.readline():
        lines = [header, handle.readline(), handle.readline(), handle.readline()]
        if not all(lines):
            raise ValueError(f"Record '{read_id(header).decode()}' is truncated: a FASTQ record is four lines.")
        yield read_id(header), b"".join(lines)


def resync(reads: Path, barcodes: Path, destination: Path) -> int:
    """Write the barcode record of every read in `reads`, returning the number written."""
    written = 0
    consumed = 0
    with gzip.open(reads, "rb") as read_handle, gzip.open(barcodes, "rb") as barcode_handle, gzip.open(destination, "wb") as out_handle:
        barcodes_left = fastq_records(barcode_handle)
        for consumed, (wanted, _record) in enumerate(fastq_records(read_handle), start=1):
            # One pass, forward only: the two streams came out of the same carmack task in the same
            # order, so a barcode read that does not turn up before the stream ends is not out of
            # order, it is absent — and either way the pairing has broken.
            for found, record in barcodes_left:
                if found == wanted:
                    out_handle.write(record)
                    written += 1
                    break
            else:
                raise ValueError(f"Read '{wanted.decode()}' survived trimming, but the barcode stream ended before its record was reached.")
    if written != consumed:
        raise ValueError(f"Resync wrote {written} barcode record(s) for {consumed} trimmed read(s); STARsolo pairs the two streams positionally.")
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reads", required=True, type=Path)
    parser.add_argument("--barcodes", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)

    try:
        resync(args.reads, args.barcodes, args.output)
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
