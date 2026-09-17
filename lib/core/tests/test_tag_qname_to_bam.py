"""Tests for `bin/tag_qname_to_bam.py`.

The script cannot be imported as part of `core`: it ships in `bin/`, which Nextflow stages onto
PATH inside the carmack container, where `core` is not installed. It is loaded by path instead.
"""

import importlib.util
import re
from pathlib import Path

import pysam
import pytest

SCRIPT = Path(__file__).resolve().parents[3] / "bin" / "tag_qname_to_bam.py"
HEADER = {"HD": {"VN": "1.6", "SO": "coordinate"}, "SQ": [{"SN": "chr21", "LN": 46709983}]}
BARCODE = "CTTGAAGAAGATACAGAGAGTGTAGCAAGT"
UMI = "ATGCTCCC"
READ_ID = "LH00235:668:23H753LT4:5:1101:39371:1014"


def load_script():
    spec = importlib.util.spec_from_file_location("tag_qname_to_bam", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tag_qname_to_bam = load_script()


def write_bam(path: Path, qnames: list[str]) -> Path:
    with pysam.AlignmentFile(str(path), "wb", header=HEADER) as writer:
        for index, qname in enumerate(qnames):
            record = pysam.AlignedSegment(writer.header)
            record.query_name = qname
            record.flag = 0
            record.reference_id = 0
            record.reference_start = 1000 + index
            record.mapping_quality = 60
            record.cigarstring = "10M"
            record.query_sequence = "ACGTACGTAC"
            record.query_qualities = pysam.qualitystring_to_array("IIIIIIIIII")
            writer.write(record)
    return path


def test_well_formed_qname_becomes_tags(tmp_path):
    source = write_bam(tmp_path / "in.bam", [f"{READ_ID}|CB={BARCODE}|UR={UMI}"])
    destination = tmp_path / "out.bam"

    assert tag_qname_to_bam.retag_bam(source, destination) == 1

    with pysam.AlignmentFile(str(destination)) as reader:
        record = next(iter(reader))
    assert record.query_name == READ_ID
    assert "|" not in record.query_name
    assert record.get_tag("CB") == BARCODE
    # The QNAME spells the UMI `UR`, the tag is `UB`; a passthrough of the QNAME key would show here.
    assert record.get_tag("UB") == UMI
    assert not record.has_tag("UR")


def test_missing_cb_is_an_error_naming_the_read(tmp_path):
    qname = f"{READ_ID}|UR={UMI}"
    source = write_bam(tmp_path / "in.bam", [qname])

    with pytest.raises(ValueError, match=re.escape(qname)):
        tag_qname_to_bam.retag_bam(source, tmp_path / "out.bam")


def test_missing_ur_is_an_error_naming_the_read(tmp_path):
    qname = f"{READ_ID}|CB={BARCODE}"
    source = write_bam(tmp_path / "in.bam", [qname])

    with pytest.raises(ValueError, match=re.escape(qname)):
        tag_qname_to_bam.retag_bam(source, tmp_path / "out.bam")


def test_main_reports_the_offending_read_and_exits_non_zero(tmp_path, capsys):
    qname = f"{READ_ID}|CB={BARCODE}"
    source = write_bam(tmp_path / "in.bam", [qname])

    exit_code = tag_qname_to_bam.main(["--input", str(source), "--output", str(tmp_path / "out.bam")])

    assert exit_code == 1
    assert qname in capsys.readouterr().err
