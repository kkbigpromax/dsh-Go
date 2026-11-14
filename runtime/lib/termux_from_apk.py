"""Recover the unchanged Termux JNI libraries from the pinned upstream APK.

The old .deb files have disappeared from Termux's rolling pool. Only native
libraries and their notices are reused; the DSH engine is still rebuilt.
"""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile


APK_SHA256 = "43324a45ec4b36495687e81070ea6a08025643509edbd1733e79e48c7fa429b1"
APK_URL = "https://github.com/ccch1mneyyy/dsh-Go/releases/download/v1.0.16/dsh-go-1.0.16-arm64.apk"
LIBRARIES = ("libproot.so", "libproot-loader.so", "libtalloc.so", "libandroid-shmem.so")
NOTICES = ("proot-COPYING.txt", "libtalloc-notice.txt", "libandroid-shmem-copyright.txt")


def recover(apk, abi, jni, licenses, metadata, versions):
    digest = hashlib.sha256()
    with apk.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != APK_SHA256:
        raise ValueError("upstream APK SHA-256 mismatch")
    with zipfile.ZipFile(apk) as archive:
        manifest = json.loads(archive.read("assets/runtime/manifest.json"))
        if manifest["abi"] != abi:
            raise ValueError("upstream APK does not contain the requested ABI")
        for key, value in zip(("prootVersion", "tallocVersion", "androidShmemVersion"), versions):
            if manifest[key] != value:
                raise ValueError("upstream APK version mismatch: " + key)
        records = {name: manifest["jniLibs"][name] for name in LIBRARIES}
        payloads = {}
        for name, record in records.items():
            data = archive.read(f"lib/{abi}/{name}")
            if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
                raise ValueError("upstream JNI manifest mismatch: " + name)
            payloads[name] = data
            record["recoveredFromApk"] = {"url": APK_URL, "sha256": APK_SHA256}
        notices = {name: archive.read("assets/runtime/licenses/" + name) for name in NOTICES}
    jni.mkdir(parents=True, exist_ok=True)
    licenses.mkdir(parents=True, exist_ok=True)
    for name, data in payloads.items():
        target = jni / name
        target.write_bytes(data)
        target.chmod(0o755)
    for name, data in notices.items():
        (licenses / name).write_bytes(data)
    metadata.write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("apk", "abi", "jni", "licenses", "metadata", "proot", "talloc", "shmem"):
        parser.add_argument(name, type=str if name in ("abi", "proot", "talloc", "shmem") else Path)
    args = parser.parse_args()
    recover(args.apk, args.abi, args.jni, args.licenses, args.metadata,
            (args.proot, args.talloc, args.shmem))
    print("Recovered four verified Termux libraries from upstream v1.0.16 APK.")


if __name__ == "__main__":
    main()
