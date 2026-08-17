##[>] 🤖🤖
from __future__ import annotations

import pytest

import catalog
import runner
from conftest import target_arch


def test_install_method(pkg, method, tier, cat, che_bin, repo):
    entry = cat.packages[pkg]
    verify = catalog.resolve_verify(entry, pkg, method)
    result = runner.run_install(pkg, method, verify, che_bin, target_arch(), repo)
    if result.skipped:
        pytest.skip(f"{pkg}: no applicable installation method for {method} here")
    assert not catalog.already_present(result.output, pkg), (
        f"{pkg} was already present in the image, {method} never ran:\n{result.output}"
    )
##[<] 🤖🤖
