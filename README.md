# PadHub

One home screen for the game apps built from your own games on iPhone and
iPad: Switch games packed with nxnative, Super Mario Sunshine with SunPad,
Melee with MeleePad, and any other app with a URL scheme.

- A carousel of game cards over a background that takes the selected game's
  colors, with a launch animation.
- Browse and launch with a controller: an NSO GameCube controller for the
  Switch 2 through [NSOGCKit](https://github.com/pookee/nso-gamecube-ios)
  (iOS has no driver for it), or any controller iOS knows. Touch works too.
- A game shows as installed when its app is on the device; your own cover
  pictures, order and hidden games are kept; games can be added by URL scheme.

Each game stays its own app: every port brings its own emulator core or
runtime, so they cannot share one binary. PadHub opens them by URL scheme:

| Game app | URL scheme |
|---|---|
| SunPad | `sunpad://` |
| MeleePad | `meleepad://` |
| nxnative game | `nxnative-<title ID in lowercase>://` |

Those apps need the scheme in their Info.plist; the `launch-links` changes in
the sibling SunPad, MeleePad and nxnative checkouts add it. A scheme that is
not in PadHub's `LSApplicationQueriesSchemes` still opens, but PadHub cannot
tell whether its app is installed.

When PadHub opens a game, the NSO controller's Bluetooth link stays up and the
game app (if it uses NSOGCKit) takes it over at once.

## Build

```sh
xcodegen generate
open PadHub.xcodeproj
```

Set your team and a bundle ID you own, then run it on a device. iOS 18 or later.
