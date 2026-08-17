##[>] 🤖🤖
from __future__ import annotations

import json
from pathlib import Path

import jsonschema
import pytest
import yaml

import catalog

REPO = Path(__file__).resolve().parent.parent

TARGETS = [
    ("linux", "amd64", "debian"),
    ("linux", "arm64", "debian"),
    ("darwin", "arm64", ""),
]


def test_catalog_matches_schema():
    schema = json.loads((REPO / "packages.schema.json").read_text())
    jsonschema.validate(yaml.safe_load(catalog.CATALOG_PATH.read_text()), schema)


def test_every_package_installs_somewhere(cat):
    unreachable = []
    for name, entry in cat.packages.items():
        if any(
            catalog.eligible_methods(entry, cat.eligible_installers(*t))
            for t in TARGETS
        ):
            continue
        unreachable.append(name)
    assert not unreachable, f"packages with no installation method on any supported platform: {unreachable}"


def test_every_verify_derives(cat):
    failures = []
    for name, entry in sorted(cat.packages.items()):
        for os_name, arch, distro in TARGETS:
            eligible = cat.eligible_installers(os_name, arch, distro)
            for mgr in catalog.eligible_methods(entry, eligible):
                try:
                    verify = catalog.resolve_verify(entry, name, mgr)
                except Exception as exc:
                    failures.append(f"{name}/{mgr} on {os_name}-{arch}: {exc}")
                    continue
                if not verify.cmds:
                    failures.append(f"{name}/{mgr} on {os_name}-{arch}: no verify command derived")
    assert not failures, "verify derivation failures:\n" + "\n".join(failures)


def test_manpages_parse(cat):
    failures = []
    for name, entry in sorted(cat.packages.items()):
        pages = list(entry.manpages) + [p for item in entry.items for p in (item.manpages or [])]
        for p in pages:
            try:
                catalog.parse_manpage(p)
            except ValueError as exc:
                failures.append(f"{name}: {exc}")
    assert not failures, "manpage failures:\n" + "\n".join(failures)


@pytest.mark.parametrize("os_name,arch,distro", TARGETS)
def test_target_has_installers(cat, os_name, arch, distro):
    assert cat.eligible_installers(os_name, arch, distro), f"no osInstallers entry for {os_name}-{arch}"
##[<] 🤖🤖
