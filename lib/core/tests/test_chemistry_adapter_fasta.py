"""Tests for `bin/chemistry_adapter_fasta.py`.

The script cannot be imported as part of `core`: it ships in `bin/`, which Nextflow stages onto
PATH inside the carmack container, where `core` is not installed. It is loaded by path instead.
"""

import importlib.util
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "bin" / "chemistry_adapter_fasta.py"
MOSAIC_END = "AGATGTGTATAAGAGACAG"
MOSAIC_END_RC = "CTGTCTCTTATACACATCT"

sys.path.insert(0, str(ROOT / "external" / "carmack"))


def load_script():
    spec = importlib.util.spec_from_file_location("chemistry_adapter_fasta", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


chemistry_adapter_fasta = load_script()


def parse(body: str) -> dict[str, str]:
    lines = body.splitlines()
    return dict(zip((n.lstrip(">") for n in lines[::2]), lines[1::2], strict=True))


class TestKnownSequences:
    def test_base_chemistry_declares_the_mosaic_end(self):
        assert known("carmack_custom_seq_1_0")["ME"] == MOSAIC_END

    def test_subclass_inherits_the_mosaic_end(self):
        # PrimD subclasses the 1.0 chemistry and imports only PRIMER_C and the class; the sequence
        # travels on the inherited read structure rather than the subclass's own module.
        assert known("carmack_custom_seq_1_0_primd")["ME"] == MOSAIC_END

    def test_carries_the_barcode_ladder_behind_the_mosaic_end(self):
        # On the scRNA arm the primers are the larger contaminant, so an ME-only FASTA would miss
        # the dominant read-through.
        assert set(known("carmack_custom_seq_1_0")) == {"ME", "PRIMER_A", "PRIMER_C"}

    def test_chemistry_without_a_mosaic_end_still_declares_its_spacers(self):
        sequences = known("hydrop")
        assert "ME" not in sequences
        assert set(sequences) == {"SPACER_1", "SPACER_2"}

    def test_unknown_chemistry_fails_loudly(self):
        with pytest.raises(ValueError, match="not supported"):
            known("no_such_chemistry")


def known(name):
    return chemistry_adapter_fasta.known_sequences(name)


class TestValidation:
    def test_length_only_placeholder_is_rejected(self):
        with pytest.raises(ValueError, match="non-ACGT"):
            chemistry_adapter_fasta.validate("N" * 19, "ME", "stub")

    def test_empty_sequence_is_rejected(self):
        with pytest.raises(ValueError, match="empty sequence"):
            chemistry_adapter_fasta.validate("", "ME", "stub")

    def test_lowercase_is_normalised(self):
        assert chemistry_adapter_fasta.validate("agatgt", "ME", "stub") == "AGATGT"

    def test_surrounding_whitespace_is_stripped(self):
        assert chemistry_adapter_fasta.validate(" AGATGT\n", "ME", "stub") == "AGATGT"


class TestReverseComplement:
    def test_mosaic_end_reverse_complement(self):
        assert chemistry_adapter_fasta.reverse_complement(MOSAIC_END) == MOSAIC_END_RC

    def test_is_an_involution(self):
        rc = chemistry_adapter_fasta.reverse_complement
        assert rc(rc(MOSAIC_END)) == MOSAIC_END


class TestRender:
    def test_every_sequence_appears_in_both_orientations(self):
        body, warning = chemistry_adapter_fasta.render("carmack_custom_seq_1_0")
        assert warning is None
        records = parse(body)
        assert records["ME"] == MOSAIC_END
        assert records["ME_rc"] == MOSAIC_END_RC
        for name in ("PRIMER_A", "PRIMER_C"):
            assert records[f"{name}_rc"] == chemistry_adapter_fasta.reverse_complement(records[name])

    def test_hydrop_renders_its_spacers_rather_than_warning(self):
        body, warning = chemistry_adapter_fasta.render("hydrop")
        assert warning is None
        assert set(parse(body)) == {"SPACER_1", "SPACER_1_rc", "SPACER_2", "SPACER_2_rc"}


class TestCli:
    def test_writes_the_fasta(self, tmp_path):
        out = tmp_path / "adapters.fasta"
        rc = chemistry_adapter_fasta.main(["--chemistry", "carmack_custom_seq_1_0", "--output", str(out)])
        assert rc == 0
        assert parse(out.read_text())["ME"] == MOSAIC_END

    def test_a_chemistry_declaring_nothing_still_writes_a_file(self, monkeypatch, tmp_path):
        # The file is always written so the Nextflow channel carrying it is never empty; an empty
        # channel would starve FASTP and the arm would silently produce no output at all.
        monkeypatch.setattr(chemistry_adapter_fasta, "known_sequences", lambda _name: {})
        out = tmp_path / "adapters.fasta"
        assert chemistry_adapter_fasta.main(["--chemistry", "bare", "--output", str(out)]) == 0
        assert out.exists()
        assert out.read_text() == ""
