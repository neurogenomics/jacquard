"""Guards the `lib/` package layout that Nextflow processes import `core` from."""

import importlib


def test_core_package_is_importable():
    assert importlib.import_module("core") is not None
