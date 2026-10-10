"""Input names become filenames and shell arguments in local and vendored modules."""

import json
import re
from pathlib import Path

import pytest

SCHEMA = json.loads((Path(__file__).resolve().parents[3] / "assets" / "schema_input.json").read_text())


@pytest.mark.parametrize("sample", ["SK609", "CONTROL_REP1", "lane-2.sample", "2026_sample"])
def test_sample_names_fit_output_filename_contract(sample):
    assert re.search(SCHEMA["items"]["properties"]["sample"]["pattern"], sample)


@pytest.mark.parametrize(
    "sample", ["", "../escape", "/absolute", "-option", ".hidden", "a b", "a;id", "a`pwd`", "a$(pwd)", 'a"b', "a*b", "a\nb", "a\n"]
)
def test_sample_names_cannot_be_shell_syntax_or_paths(sample):
    assert not re.search(SCHEMA["items"]["properties"]["sample"]["pattern"], sample)


@pytest.mark.parametrize("column", ["fastq_1", "fastq_2"])
@pytest.mark.parametrize("name", ["sample.fastq.gz", "sample_R1.fq.gz", "/directory with spaces/sample.fastq.gz", "s3://bucket/path/sample.fastq.gz"])
def test_fastq_paths_allow_safe_staged_basenames(column, name):
    assert re.search(SCHEMA["items"]["properties"][column]["pattern"], name)


@pytest.mark.parametrize("column", ["fastq_1", "fastq_2"])
@pytest.mark.parametrize(
    "name", ["$(pwd).fastq.gz", "a;id.fastq.gz", "a`pwd`.fq.gz", "a*.fastq.gz", "-option.fastq.gz", "a b.fastq.gz", "a.fastq.gz\n"]
)
def test_fastq_staged_basenames_cannot_be_shell_syntax(column, name):
    assert not re.search(SCHEMA["items"]["properties"][column]["pattern"], name)
