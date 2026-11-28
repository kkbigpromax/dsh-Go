#!/usr/bin/env bash
# Builds libxray.so (the trimmed Xray core: VLESS + REALITY, RAW/Vision and XHTTP)
# for the APK from the commit pinned in source.json.
#
#   runtime/xray/build.sh            both ABIs
#   runtime/xray/build.sh arm64-v8a  one ABI
#
# Output: runtime/out-xray/jniLibs/<abi>/libxray.so, picked up by
# app/android/app/build.gradle.kts. It is an ordinary executable named lib*.so so
# Android extracts it to nativeLibraryDir, where the app may run it (XrayProxy.kt).
# Needs git and Go (the core's go.mod asks for 1.27; GOTOOLCHAIN=auto fetches it).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT="$ROOT/runtime/out-xray/jniLibs"
SRC="$ROOT/runtime/out-xray/src"

read_json() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$HERE/source.json" "$1"; }
repo=$(read_json repository)
commit=$(read_json commit)

if [[ ! -d $SRC/.git ]]; then
  rm -rf "$SRC"
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$repo"
fi
if [[ $(git -C "$SRC" rev-parse -q --verify HEAD 2>/dev/null || true) != "$commit" ]]; then
  git -C "$SRC" fetch -q --depth 1 origin "$commit"
  git -C "$SRC" checkout -q --detach FETCH_HEAD
fi
[[ $(git -C "$SRC" rev-parse HEAD) == "$commit" ]] || { echo "xray: source is not at $commit" >&2; exit 1; }

abis=("$@")
((${#abis[@]})) || abis=(arm64-v8a x86_64)
for abi in "${abis[@]}"; do
  case $abi in
    arm64-v8a) goos=android arch=arm64 ;;
    # android/amd64 needs cgo; a static linux build runs on the x86_64 emulator.
    x86_64) goos=linux arch=amd64 ;;
    *) echo "xray: unknown ABI $abi" >&2; exit 2 ;;
  esac
  mkdir -p "$OUT/$abi"
  echo "xray: building $abi from ${commit:0:12}"
  (cd "$SRC" && CGO_ENABLED=0 GOOS=$goos GOARCH=$arch \
    go build -o "$OUT/$abi/libxray.so" -trimpath -buildvcs=false -ldflags="-s -w -buildid=" ./main)
done
