##[>] 🤖🤖
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml

CATALOG_PATH = Path(__file__).resolve().parent.parent / "packages.yml"

MANPAGE_EXTS = (".gz", ".bz2", ".xz", ".zst")

VERSION_MANAGERS = ("pyenv", "nvm")


@dataclass
class Item:
    mgr: str
    name: str = ""
    version: str = ""
    verify: dict | None = None
    manpages: list[str] | None = None
    versions: list[str] = field(default_factory=list)
    apt_package_name: str = ""
    nix_package_name: str = ""


@dataclass
class Entry:
    items: list[Item] = field(default_factory=list)
    version: str = ""
    command: str = ""
    version_command: str = ""
    verify: dict | None = None
    manpages: list[str] = field(default_factory=list)


@dataclass
class Catalog:
    os_installers: dict[str, list[str]]
    packages: dict[str, Entry]
    tool_packages: dict[str, dict[str, str]]

    def eligible_installers(self, os_name: str, arch: str, distro: str = "") -> list[str]:
        keys = []
        if distro:
            keys += [f"{os_name}-{distro}-{arch}", f"{os_name}-{distro}"]
        keys += [f"{os_name}-{arch}", os_name]
        for key in keys:
            if key in self.os_installers:
                return self.os_installers[key]
        return []


def parse_manpage(name: str) -> tuple[str, str]:
    trimmed = name
    for ext in MANPAGE_EXTS:
        if trimmed.endswith(ext):
            trimmed = trimmed[: -len(ext)]
            break
    i = trimmed.rfind(".")
    if i <= 0 or i == len(trimmed) - 1:
        raise ValueError(f"manpage {name!r}: want <name>.<section>")
    base, section = trimmed[:i], trimmed[i + 1 :]
    if not section[0].isdigit():
        raise ValueError(f"manpage {name!r}: section must start with a digit")
    return base, section


def _installer_key(mgr: str) -> str:
    return "brew/cask" if mgr == "cask" else mgr


def _method_key(mgr: str) -> str:
    if mgr == "brew":
        return "brew/formulae"
    if mgr == "cask":
        return "brew/cask"
    return mgr


def _parse_item(node) -> Item:
    if isinstance(node, str):
        mgr = "cask" if node == "brew/cask" else node
        return Item(mgr=mgr)
    if not isinstance(node, dict) or len(node) != 1:
        raise ValueError(f"manager item must be a scalar or single-key map: {node!r}")
    key, val = next(iter(node.items()))
    mgr = "cask" if key == "brew/cask" else key
    if val is None:
        return Item(mgr=mgr)
    if key == "script" and isinstance(val, str):
        return Item(mgr="script")
    body = val if isinstance(val, dict) else {}
    item = Item(
        mgr=mgr,
        name=body.get("packageName", "") or "",
        version=body.get("version", "") or "",
        verify=body.get("verify"),
        manpages=(list(body["manpages"]) if "manpages" in body else None),
        versions=[str(v) for v in (body.get("versions") or [])],
    )
    if key == "apt":
        item.apt_package_name = body.get("packageName", "") or ""
    if key == "nix":
        item.nix_package_name = body.get("packageName", "") or ""
    return item


def _parse_entry(node) -> Entry:
    if isinstance(node, list):
        return Entry(items=[_parse_item(i) for i in node])
    if not isinstance(node, dict):
        raise ValueError(f"entry must be a list or map: {node!r}")
    return Entry(
        items=[_parse_item(i) for i in (node.get("installers") or [])],
        version=str(node.get("version", "") or ""),
        command=node.get("command", "") or "",
        version_command=node.get("versionCommand", "") or "",
        verify=node.get("verify"),
        manpages=list(node.get("manpages") or []),
    )


def _flatten(node) -> list[str]:
    out: list[str] = []
    for el in node or []:
        if isinstance(el, list):
            out += _flatten(el)
        else:
            out.append(el)
    return out


def load(path: Path = CATALOG_PATH) -> Catalog:
    raw = yaml.safe_load(path.read_text())
    return Catalog(
        os_installers={k: _flatten(v) for k, v in (raw.get("osInstallers") or {}).items()},
        packages={name: _parse_entry(node) for name, node in (raw.get("packages") or {}).items()},
        tool_packages={
            tool: {name: str(ver) for name, ver in (pkgs or {}).items()}
            for tool, pkgs in (raw.get("toolPackages") or {}).items()
        },
    )


def eligible_methods(entry: Entry, eligible: list[str], selected: str = "") -> list[str]:
    methods: list[str] = []
    for item in entry.items:
        if item.mgr in methods:
            continue
        if _installer_key(item.mgr) not in eligible:
            continue
        if not matches_method(_method_key(item.mgr), selected):
            continue
        methods.append(item.mgr)
    return methods


def matches_method(key: str, selected: str) -> bool:
    if not selected or selected == "all":
        return True
    return key == selected or key.startswith(selected + "/")


@dataclass
class VerifyCmd:
    cmd: str
    want_out: bool = False


@dataclass
class Verify:
    cmds: list[VerifyCmd] = field(default_factory=list)
    bin: str = ""
    check_path: bool = True


def _default_verify(entry: Entry, pkg: str) -> VerifyCmd:
    cmd = entry.command or pkg
    return VerifyCmd(cmd=f"{cmd} --version 2>/dev/null || {cmd} version", want_out=True)


def pkg_mgr_version_check(entry: Entry, pkg: str, mgr: str) -> str:
    name = pkg
    for item in entry.items:
        if item.mgr != mgr:
            continue
        if item.apt_package_name:
            name = item.apt_package_name
        elif item.nix_package_name:
            name = item.nix_package_name
        elif item.name:
            name = item.name
    if mgr == "apt":
        return f"dpkg-query -W -f '${{Version}}\\n' {name}"
    if mgr == "brew":
        if entry.version:
            return f"brew list --versions {name}@{entry.version} || brew list --versions {name}"
        return f"brew list --versions {name}"
    if mgr == "cask":
        return f"brew list --cask --versions {name}"
    if mgr == "npm":
        return f"npm ls --global {name}"
    if mgr == "nix":
        return f"nix profile list | grep -i {name}"
    raise ValueError(f"verify pkgMgrVersionCheck: no version query for method {mgr}")


def resolve_verify(entry: Entry, pkg: str, mgr: str) -> Verify:
    spec = entry.verify
    for item in entry.items:
        if item.mgr == mgr and item.verify is not None:
            spec = item.verify

    name = entry.command or pkg
    check_path = True if spec is None else spec.get("checkInPath", True)
    out = Verify(bin=name, check_path=bool(check_path))

    if spec is not None:
        if spec.get("versionCmd"):
            out.cmds.append(_default_verify(entry, pkg))
        if spec.get("pkgMgrVersionCheck"):
            out.cmds.append(VerifyCmd(cmd=pkg_mgr_version_check(entry, pkg, mgr), want_out=True))
        if spec.get("cmd"):
            out.cmds.append(VerifyCmd(cmd=spec["cmd"]))
    if not out.cmds:
        if spec is None and entry.version_command:
            out.cmds = [VerifyCmd(cmd=entry.version_command, want_out=True)]
        elif mgr in VERSION_MANAGERS:
            for item in entry.items:
                if item.mgr != mgr:
                    continue
                for v in item.versions:
                    if mgr == "pyenv":
                        out.cmds.append(VerifyCmd(cmd=f'pyenv versions --bare | grep -Fx "{v}"', want_out=True))
                    else:
                        out.cmds.append(
                            VerifyCmd(cmd=f'test -x "$NVM_DIR/versions/node/v{v}/bin/node" && echo v{v}', want_out=True)
                        )
            out.cmds.append(_default_verify(entry, pkg))
        else:
            out.cmds = [_default_verify(entry, pkg)]

    pages = list(entry.manpages)
    for item in entry.items:
        if item.mgr == mgr and item.manpages is not None:
            pages = item.manpages
    for p in pages:
        base, section = parse_manpage(p)
        out.cmds.append(VerifyCmd(cmd=f"man -w {section} {base}", want_out=True))
    return out


INSTALLED_RE = "installed {pkg}( \\S+)? via "


def already_present(output: str, pkg: str) -> bool:
    stripped = strip_ansi(output)
    if re.search(INSTALLED_RE.format(pkg=re.escape(pkg)), stripped, re.M):
        return False
    return f"will not install {pkg}:" in stripped or f"{pkg}: ✅ already" in stripped


ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def strip_ansi(s: str) -> str:
    return ANSI_RE.sub("", s)
##[<] 🤖🤖
