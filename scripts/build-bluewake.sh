#!/bin/bash
# Builds BlueWakeGame.framework, Wind Waker inside PadHub (Games/BlueWake), from
# the sibling BlueWake checkout with the settings its builder uses for the
# BlueWake app (scripts/builder/profiles/bluewake.sh). Run BlueWake's builder
# first: it fetches the dependencies and makes the game module from your disc
# (scripts/builder/build.sh DISC.iso --out build/device). PadHub's build phase
# (stage-games.sh) then puts the framework and the module in PadHub.app.
#   scripts/build-bluewake.sh [bundle-id]    (PadHub's, default org.padhub.app)
# NSOGCKIT_FRAMEWORK_DIR: the folder with PadHub's own NSOGCKit.framework for
# iPhone (by default the last Release build in build/DerivedData).
set -euo pipefail

padhub=$(cd "$(dirname "$0")/.." && pwd)
bluewake=${BLUEWAKE_ROOT:-$padhub/../bluewake}
bundle_id=${1:-org.padhub.app}
nsogckit=${NSOGCKIT_FRAMEWORK_DIR:-$padhub/build/DerivedData/Build/Products/Release-iphoneos}
out=$bluewake/build/padhub

[ -d "$nsogckit/NSOGCKit.framework" ] || { echo "error: no NSOGCKit.framework in $nsogckit: build PadHub for iPhone first" >&2; exit 1; }
dawn=$bluewake/build/deps/dawn-ios/lib/cmake/Dawn
[ -d "$dawn" ] || { echo "error: run BlueWake's builder first (no Dawn in $dawn)" >&2; exit 1; }
# The host profile the builder used, when there is one.
flags=""
profile=$(ls "$bluewake"/build/device/profiles/host-*.profdata 2>/dev/null | head -1 || true)
if [ -n "$profile" ]; then
  flags="-fprofile-instr-use=$profile -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date -Wno-backend-plugin -mllvm -enable-machine-outliner=never"
fi

cmake -S "$bluewake/apple/ios" -B "$out" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=OFF -DPNG_SHARED=OFF \
  -DBLUEWAKE_TVOS=OFF \
  -DAURORA_DAWN_PROVIDER=system "-DDawn_DIR=$dawn" \
  -DAURORA_SDL3_PROVIDER=vendor -DAURORA_SDL3_LINKAGE=static -DAURORA_DAWN_LINKAGE=static \
  "-DCMAKE_C_FLAGS=$flags" "-DCMAKE_CXX_FLAGS=$flags" \
  '-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local' -DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=ON \
  -DBLUEWAKE_PADHUB=ON "-DPADHUB_DIR=$padhub" "-DPADHUB_BUNDLE_ID=$bundle_id" \
  "-DNSOGCKIT_FRAMEWORK_DIR=$nsogckit"
cmake --build "$out" --target BlueWakeGame
echo "BlueWakeGame.framework: $out/BlueWakeGame.framework"
