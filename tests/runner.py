##[>] 🤖🤖
from __future__ import annotations

import fcntl
import os
import shlex
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from catalog import Verify

SKIP_MARKER = "CHE_E2E_SKIP_NO_APPLICABLE_MANAGER"

BASE_IMAGE = os.environ.get("CHE_E2E_IMAGE", "che-packages-base")

DOCKERFILE = Path(__file__).resolve().parent / "install-base.Dockerfile"


def ensure_image(arch: str) -> str:
    """Build the install base image (debian plus man-db) once per arch, tagged by arch.

    1. Return the tag untouched when CHE_E2E_IMAGE names an image to use as-is.
    2. Take an exclusive file lock, so parallel workers build the tag once between them.
    3. Return the tag when docker already has it, build it from install-base.Dockerfile otherwise.

    Interfaces with:
      - `$ docker image inspect` / `$ docker build` — the local docker daemon
    """
    if os.environ.get("CHE_E2E_IMAGE"):
        return BASE_IMAGE
    tag = f"{BASE_IMAGE}:{arch}"
    lock = Path(tempfile.gettempdir()) / f"che-packages-image-{arch}.lock"
    with open(lock, "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        if subprocess.run(["docker", "image", "inspect", tag], capture_output=True).returncode != 0:
            build = subprocess.run(
                ["docker", "build", "--platform", f"linux/{arch}",
                 "--tag", tag, "-"],
                stdin=DOCKERFILE.open("rb"),
                capture_output=True, text=True,
                env=os.environ | {"DOCKER_BUILDKIT": "1"},
            )
            if build.returncode != 0:
                raise AssertionError(
                    f"docker build {tag} failed (exit {build.returncode}):\n{build.stdout}{build.stderr}"
                )
    return tag

ENV_PRELUDE = """export HOME=/root
export PATH=/root/.local/bin:/root/go/bin:/root/.pyenv/bin:/root/.pyenv/shims:/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:$PATH
export XDG_CONFIG_HOME=/root/.config XDG_DATA_HOME=/root/.local/share XDG_BIN_HOME=/root/.local/bin
export XDG_STATE_HOME=/root/.local/state XDG_CACHE_HOME=/root/.cache
export PYENV_ROOT=/root/.pyenv NVM_DIR=/root/.config/nvm GOBIN=/root/go/bin GOFLAGS=-modcacherw
export CHE_E2E=1 CHE_PACKAGES_BINARIES_REMOTE_ARCHIVE_CHECK_PRESENT_ON_PATH=0
mkdir -p /root/.local/bin /root/.config /root/.local/state /tmp/work
cd /tmp/work
printf 'e2e:\\n  options: {autoDiscover: true}\\n' > che.yml
"""


def verify_shell(cmd: str) -> str:
    return (
        'if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh"; fi; '
        "if [ -s /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; "
        "then . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; fi; "
        'if [ -d "$HOME/.local/share/man" ]; then export MANPATH="$HOME/.local/share/man:"; fi; '
    ) + cmd


@dataclass
class Result:
    output: str
    skipped: bool


def _install_argv(pkg: str, method: str, kind: str = "") -> list[str]:
    argv = ["packages", "install", "--packages-file", "/work/packages.yml", "--missing-method-warn"]
    if kind:
        argv += ["--kind", kind]
    argv += ["--only-methods", method, pkg]
    return argv


def build_script(pkg: str, method: str, verify: Verify, log_level: str, kind: str = "") -> str:
    lines = [ENV_PRELUDE, f"export CHE_LOG_LEVEL={log_level}"]
    argv = " ".join(shlex.quote(a) for a in _install_argv(pkg, method, kind))
    lines.append("olog=$(mktemp) rcf=$(mktemp)")
    lines.append(f'{{ che {argv} 2>&1; echo $? > "$rcf"; }} | tee "$olog"')
    lines.append('[ "$(cat "$rcf")" = 0 ] || exit 1')
    lines.append('out=$(cat "$olog")')
    lines.append("m='no applicable installation'' method'")
    lines.append(f'case "$out" in (*"{pkg}: $m"*) echo {SKIP_MARKER}; exit 0;; esac')
    for v in verify.cmds:
        label = f"verify {pkg} via `{v.cmd}`"
        shell = shlex.quote(verify_shell(v.cmd))
        lines.append(
            f"vout=$(bash -c {shell} 2>&1) || {{ printf '%s: %s ❌\\n' {shlex.quote(label)} \"$vout\"; exit 1; }}"
        )
        lines.append(f"printf '%s: %s ✅\\n' {shlex.quote(label)} \"$vout\"")
        if v.want_out:
            lines.append('test -n "$vout"')
    if verify.check_path:
        b = verify.bin
        lines.append(
            f"if p=$(command -v {b}); then printf 'verify {b} on PATH: %s ✅\\n' \"$p\"; "
            f"else printf 'verify {b} not on PATH ❌\\n'; exit 1; fi"
        )
    else:
        lines.append(f"printf 'verify {pkg} on PATH: skipped (checkInPath: false)\\n'")
    return "\n".join(lines)


def cache_dir() -> Path:
    base = Path(os.environ.get("E2E_INSTALL_CACHE_DIR", Path.home() / ".cache" / "che" / "dev"))
    base = base / os.environ.get("PYTEST_XDIST_WORKER", "gw0")
    for sub in ("apt-cache", "apt-lists", "xdg", "downloads"):
        (base / sub).mkdir(parents=True, exist_ok=True)
    return base


def run_install(pkg: str, method: str, verify: Verify, che_bin: Path, arch: str, repo: Path, kind: str = "") -> Result:
    cache = cache_dir()
    script = build_script(pkg, method, verify, os.environ.get("CHE_LOG_LEVEL", "info"), kind)
    argv = [
        "docker", "run", "--rm", "--platform", f"linux/{arch}",
        "-v", f"{che_bin}:/usr/local/bin/che:ro",
        "-v", f"{repo}:/work:ro",
        "-v", f"{cache / 'apt-cache'}:/var/cache/apt",
        "-v", f"{cache / 'apt-lists'}:/var/lib/apt/lists",
        "-v", f"{cache / 'xdg'}:/root/.cache",
        "-v", f"{cache / 'downloads'}:/che-cache",
        "-e", "CHE_PACKAGES_DOWNLOAD_CACHE_DIR=/che-cache",
        ensure_image(arch), "sh", "-ec", script,
    ]
    print(f"\n=== install {pkg} via {method} ({arch}) ===", flush=True)
    lines: list[str] = []
    proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    assert proc.stdout is not None
    for line in proc.stdout:
        print(line, end="", flush=True)
        lines.append(line)
    code = proc.wait()
    out = "".join(lines)
    if code != 0:
        raise AssertionError(f"install {pkg} via {method} failed (exit {code}):\n{out}")
    return Result(output=out, skipped=SKIP_MARKER in out)
##[<] 🤖🤖
