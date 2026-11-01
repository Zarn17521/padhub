#!/bin/sh
# Xcode build phase: puts the game modules made from your own discs at the top
# of PadHub.app, where SunPad and MeleePad look for them, and signs them. They
# come from Modules/ (never committed), else from the sibling checkouts' own
# builds. A game whose module is missing shows as not installed.
set -eu

app="$TARGET_BUILD_DIR/$WRAPPER_NAME"
sunpad="$SRCROOT/../sunpad"

stage() {
  name="$1"
  shift
  for source in "$SRCROOT/Modules/$name" "$@"; do
    if [ -f "$source" ]; then
      cp -f "$source" "$app/$name"
      if [ -f "$source.dol-sha256" ]; then
        cp -f "$source.dol-sha256" "$app/$name.dol-sha256"
      fi
      if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$app/$name"
      fi
      echo "Staged $name from $source"
      return
    fi
  done
  rm -f "$app/$name" "$app/$name.dol-sha256"
  echo "warning: $name is missing; put it in Modules/ to play that game"
}

if [ "$PLATFORM_NAME" = iphonesimulator ]; then
  # Simulator modules, from each game's scripts/ios-build-core.sh.
  stage_simulator() {
    if [ -f "$2" ]; then
      cp -f "$2" "$app/$1"
      [ ! -f "$2.dol-sha256" ] || cp -f "$2.dol-sha256" "$app/$1.dol-sha256"
      codesign --force --sign - --timestamp=none "$app/$1"
      echo "Staged $1 from $2"
    else
      rm -f "$app/$1" "$app/$1.dol-sha256"
      echo "warning: $1 is missing for the Simulator"
    fi
  }
  stage_simulator gGMSE01_recomp.dylib /tmp/sunpad-module-ios-simulator/gGMSE01_recomp.dylib
  stage_simulator gGALE01r2_recomp.dylib /tmp/meleepad-module-ios-simulator-r2/gGALE01_recomp.dylib
  exit 0
fi

stage gGMSE01_recomp.dylib "$sunpad/build/ios-module-device/gGMSE01_recomp.dylib"
stage gGALE01r2_recomp.dylib /tmp/meleepad-module-ios-device-r2/gGALE01_recomp.dylib
