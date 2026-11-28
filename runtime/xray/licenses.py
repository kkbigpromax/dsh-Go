#!/usr/bin/env python3
"""Writes app/assets/licenses/xray-core-NOTICE.txt for the App's 开源许可 page.

Run after runtime/xray/build.sh whenever source.json moves:

    python3 runtime/xray/licenses.py

It reads the Go modules actually linked into the built libxray.so
(`go version -m`) and copies each one's licence text from the Go module cache,
after the core's own MPL-2.0 text and where its source is.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BINARY = ROOT / 'runtime/out-xray/jniLibs/arm64-v8a/libxray.so'
SOURCE = ROOT / 'runtime/out-xray/src'
OUT = ROOT / 'app/assets/licenses/xray-core-NOTICE.txt'


def escaped(path):
    """The module cache's case encoding: an upper-case letter becomes '!' + lower."""
    return ''.join('!' + c.lower() if c.isupper() else c for c in path)


def main():
    source = json.loads((HERE / 'source.json').read_text())
    if not BINARY.exists():
        sys.exit('xray licenses: build libxray.so first (runtime/xray/build.sh)')
    info = subprocess.run(['go', 'version', '-m', str(BINARY)], check=True, capture_output=True, text=True).stdout
    deps = [line.split()[1:3] for line in info.splitlines() if line.split()[:1] == ['dep']]
    cache = Path(subprocess.run(['go', 'env', 'GOMODCACHE'], check=True, capture_output=True, text=True).stdout.strip())
    parts = [
        f"Xray-core (trimmed: VLESS + REALITY), {source['version']}\n"
        f"Source: {source['repository']} at commit {source['commit']}\n"
        "Built as libxray.so by runtime/xray/build.sh; it runs as the local proxy behind 设置 › 代理.\n"
        "Licensed under the Mozilla Public License 2.0; the source of every file is at the commit above.\n",
        (SOURCE / 'LICENSE').read_text(),
        "\nThe Go modules linked into libxray.so, each under its own licence:\n",
    ]
    for path, version in deps:
        folder = cache / f'{escaped(path)}@{version}'
        licence = next((p for name in ('LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING') if (p := folder / name).exists()), None)
        if licence is None:
            sys.exit(f'xray licenses: no licence file for {path}@{version}')
        parts.append(f'\n----- {path} {version} -----\n\n{licence.read_text()}')
    OUT.write_text('\n'.join(parts))
    print(f'wrote {OUT.relative_to(ROOT)}: {len(deps)} modules')


if __name__ == '__main__':
    main()
