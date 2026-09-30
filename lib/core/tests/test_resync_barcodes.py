"""Tests for `bin/resync_barcodes.py`.

The script cannot be imported as part of `core`: it ships in `bin/`, which Nextflow stages onto
PATH inside a bare python container, where `core` is not installed. It is loaded by path instead.
"""

import gzip
import importlib.util
import re
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[3] / "bin" / "resync_barcodes.py"
BARCODE = "CTTGAAGAAGATACAGAGAGTGTAGCAAGT"
READS = [
    "LH00235:668:23H753LT4:5:1101:39371:1014",
    "LH00235:668:23H753LT4:5:1101:47882:1014",
    "LH00235:668:23H753LT4:5:1101:51232:1014",
]


def load_script():
    spec = importlib.util.spec_from_file_location("resync_barcodes", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


resync_barcodes = load_script()


def write_fastq(path: Path, records: list[tuple[str, str]]) -> Path:
    with gzip.open(path, "wt") as handle:
        for header, sequence in records:
            handle.write(f"@{header}\n{sequence}\n+\n{'I' * len(sequence)}\n")
    return path


def barcode_records(read_ids: list[str]) -> list[tuple[str, str]]:
    return [(read_id, f"{BARCODE}ATGCTCC{index}") for index, read_id in enumerate(read_ids)]


def cdna_records(read_ids: list[str]) -> list[tuple[str, str]]:
    # fastp leaves the header as it found it, and carmack's R1 carries the Illumina comment the
    # barcode read does not, so the two only line up once the comment is stripped.
    return [(f"{read_id}/1 1:N:0:TATAGCCT", "ACGTACGTACGTACGTACGT") for read_id in read_ids]


def read_headers(path: Path) -> list[str]:
    with gzip.open(path, "rt") as handle:
        return [line.rstrip("\n")[1:] for index, line in enumerate(handle) if index % 4 == 0]


def test_untrimmed_stream_is_copied_verbatim(tmp_path):
    barcodes = write_fastq(tmp_path / "barcodes.fastq.gz", barcode_records(READS))
    reads = write_fastq(tmp_path / "r1.fastq.gz", cdna_records(READS))
    destination = tmp_path / "out.fastq.gz"

    assert resync_barcodes.resync(reads, barcodes, destination) == 3

    # Verbatim rather than re-rendered: STARsolo reads the barcode and the UMI off fixed offsets of
    # this record, so any rewriting of it is a silent change to every cell the run calls.
    assert gzip.decompress(destination.read_bytes()) == gzip.decompress(barcodes.read_bytes())


def test_reads_trimming_dropped_leave_their_barcodes_behind(tmp_path):
    barcodes = write_fastq(tmp_path / "barcodes.fastq.gz", barcode_records(READS))
    reads = write_fastq(tmp_path / "r1.fastq.gz", cdna_records([READS[0], READS[2]]))
    destination = tmp_path / "out.fastq.gz"

    assert resync_barcodes.resync(reads, barcodes, destination) == 2
    assert read_headers(destination) == [READS[0], READS[2]]


def test_a_read_the_barcode_stream_never_carried_is_an_error(tmp_path):
    barcodes = write_fastq(tmp_path / "barcodes.fastq.gz", barcode_records(READS[:2]))
    reads = write_fastq(tmp_path / "r1.fastq.gz", cdna_records(READS))

    with pytest.raises(ValueError, match=re.escape(READS[2])):
        resync_barcodes.resync(reads, barcodes, tmp_path / "out.fastq.gz")


def test_a_reordered_barcode_stream_is_an_error(tmp_path):
    # The scan is forward-only in one pass, so a barcode read out of order is indistinguishable
    # from one that is missing — and either way the pairing STARsolo depends on has broken.
    barcodes = write_fastq(tmp_path / "barcodes.fastq.gz", barcode_records([READS[1], READS[0], READS[2]]))
    reads = write_fastq(tmp_path / "r1.fastq.gz", cdna_records(READS))

    # The first read is still found, further down the stream; the second is then behind the scan.
    with pytest.raises(ValueError, match=re.escape(READS[1])):
        resync_barcodes.resync(reads, barcodes, tmp_path / "out.fastq.gz")


def test_main_reports_the_unmatched_read_and_exits_non_zero(tmp_path, capsys):
    barcodes = write_fastq(tmp_path / "barcodes.fastq.gz", barcode_records(READS[:2]))
    reads = write_fastq(tmp_path / "r1.fastq.gz", cdna_records(READS))

    exit_code = resync_barcodes.main(["--reads", str(reads), "--barcodes", str(barcodes), "--output", str(tmp_path / "out.fastq.gz")])

    assert exit_code == 1
    assert READS[2] in capsys.readouterr().err
