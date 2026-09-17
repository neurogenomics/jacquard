#!/usr/bin/env python3
"""Write the selected chemistry's known sequences as a FASTA for fastp to trim against.

Self-contained on carmack and the standard library, in the style of the other `bin/` scripts: it
runs inside the carmack container, where the `core` package is not installed.

Every sequence the chemistry declares is emitted, not just the Mosaic End. Read-through runs from
the insert into ME and then on through the barcode ladder behind it, and on the scRNA arm the
primers are the larger contaminant of the two: measured on the SK609 fixtures, R2 carries 5.75%
PRIMER_A against 2.04% ME.
"""

import argparse
import sys

from carmack.chemistry.chemistry_factory import ChemistryFactory

COMPLEMENT = str.maketrans("ACGT", "TGCA")


def known_sequences(chemistry_name: str) -> dict[str, str]:
    """The chemistry's declared sequences, keyed by component name."""
    chemistry = ChemistryFactory.get_chemistry(chemistry_name)
    return chemistry.read_structure.get_known_sequences()


def validate(sequence: str, name: str, chemistry_name: str) -> str:
    """Reject a declared sequence that cannot be used as an adapter.

    A component that declares nothing is legitimate and never reaches here. One that declares a
    value this cannot trim with means the chemistry changed into a shape this script does not
    understand, which must fail rather than quietly trim nothing while looking configured.
    """
    normalised = sequence.strip().upper()
    if not normalised:
        raise ValueError(f"Chemistry '{chemistry_name}' declares an empty sequence for {name}.")
    if set(normalised) - set("ACGT"):
        raise ValueError(
            f"Chemistry '{chemistry_name}' declares a non-ACGT sequence for {name}: "
            f"'{sequence}'. Refusing to use it as an adapter."
        )
    return normalised


def reverse_complement(sequence: str) -> str:
    return sequence.translate(COMPLEMENT)[::-1]


def render(chemistry_name: str) -> tuple[str, str | None]:
    """The FASTA body for a chemistry, and a warning when it declares no sequences at all.

    The body is empty rather than absent in that case: the caller always writes the file, so the
    Nextflow channel carrying it is never empty and cannot starve the process downstream of it.
    """
    sequences = known_sequences(chemistry_name)
    if not sequences:
        return "", (
            f"Chemistry '{chemistry_name}' declares no known sequences; fastp will fall back to "
            f"read-pair overlap detection alone."
        )
    records = []
    for name, sequence in sequences.items():
        adapter = validate(sequence, name, chemistry_name)
        # fastp matches an adapter_fasta entry as given and never reverse-complements it, while
        # read-through reaches R2 as the reverse complement — 14.30% of scTIP R2 against 0.07%
        # in the forward orientation.
        records.append(f">{name}\n{adapter}\n")
        records.append(f">{name}_rc\n{reverse_complement(adapter)}\n")
    return "".join(records), None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chemistry", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    body, warning = render(args.chemistry)
    with open(args.output, "w") as handle:
        handle.write(body)
    if warning:
        print(warning, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
