##[>] 🤖🤖
from __future__ import annotations

import os
import platform
from pathlib import Path

import pytest

import catalog

REPO = Path(__file__).resolve().parent.parent

AUTO_PER_METHOD = int(os.environ.get("CHE_E2E_AUTO_PER_METHOD", "2"))

#[why] the che binary under test is mounted onto the container's PATH, so che's own entry can
#   never install here: che reports it already present and the method never runs. Testing it
#   would need a container without che, which is the one thing this harness cannot provide
SELF_INSTALL = {"che"}


def pytest_addoption(parser):
    parser.addoption("--package", default="", help="only this package (comma-separated)")
    parser.addoption("--method", default="", help="only this install method")
    parser.addoption("--tier", default="", choices=["", "auto", "manual", "all"],
                     help="auto: the first N packages per method; manual: the rest; all: both")


def _host_arch() -> str:
    return "arm64" if platform.machine() in ("arm64", "aarch64") else "amd64"


def target_arch() -> str:
    return os.environ.get("TARGET_ARCH", _host_arch())


@pytest.fixture(scope="session")
def cat() -> catalog.Catalog:
    return catalog.load()


@pytest.fixture(scope="session")
def che_bin() -> Path:
    p = Path(os.environ.get("CHE_BIN", REPO / ".user" / "bin" / "che"))
    if not p.exists():
        pytest.skip(f"che binary absent at {p}; set CHE_BIN or run make fetch-che")
    return p


@pytest.fixture(scope="session")
def repo() -> Path:
    return REPO


def _cases(config) -> list[tuple[str, str, str]]:
    cat = catalog.load()
    eligible = cat.eligible_installers("linux", target_arch(), "debian")
    only_pkgs = [p.strip() for p in (config.getoption("--package") or "").split(",") if p.strip()]
    method_sel = config.getoption("--method") or ""
    tier = config.getoption("--tier") or os.environ.get("CHE_E2E_TIER", "all")

    used: dict[str, int] = {}
    cases = []
    for name in sorted(cat.packages):
        if name in SELF_INSTALL:
            continue
        entry = cat.packages[name]
        for mgr in catalog.eligible_methods(entry, eligible, method_sel):
            key = catalog._method_key(mgr)
            used[key] = used.get(key, 0) + 1
            got = "auto" if used[key] <= AUTO_PER_METHOD else "manual"
            if tier in ("auto", "manual") and got != tier:
                continue
            if only_pkgs and name not in only_pkgs:
                continue
            cases.append((name, mgr, got))
    return cases


def pytest_generate_tests(metafunc):
    if {"pkg", "method"} <= set(metafunc.fixturenames):
        cases = _cases(metafunc.config)
        metafunc.parametrize(
            "pkg,method,tier",
            cases,
            ids=[f"{p}-{catalog._method_key(m)}-{t}" for p, m, t in cases],
        )
##[<] 🤖🤖
