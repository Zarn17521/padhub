# PadHub

One app for the games you made from your own discs on iPhone and iPad:
Super Mario Sunshine (SunPad) and Super Smash Bros. Melee (MeleePad) are
built into it, and Switch games packed with nxnative open from it.

- A carousel of the games' box art over a background that takes the selected
  game's colors, with a launch animation. The box art comes from
  [GameTDB](https://www.gametdb.com) the first time PadHub runs; a picture of
  your own replaces it (Settings).
- Browse and play with a controller: NSO GameCube controllers for the Switch 2
  through [NSOGCKit](https://github.com/pookee/nso-gamecube-ios) (iOS has no
  driver for them), or any controller iOS knows. Touch works too.
- Leave a game from its menu (Back to PadHub) or with the NSO controller's
  HOME button: it waits, paused, behind the menu. A to resume it, HOME to go
  straight back, Close game to end it. Starting another game asks to close
  the paused one first.

## How the games fit in one app

Each game's emulator core (a Dolphin build per game, plus the module made from
your disc) defines the same symbols as the others, so each core is a framework
of its own (`SunPadGame`, `MeleePadGame`) that exports nothing but its
`PadHubGame` class (`Games/*/exports.txt`). PadHub embeds them without linking
them and loads one the first time its game opens. `Games/PadHubGame.h` is the
whole interface between the menu and a game; `Games/*/…HubGame.mm` does for
each game what its own app delegate does in the standalone app.

NSOGCKit is a framework too, shared by the menu and the games, so its classes
exist once. The menu reads the controllers' state on each screen refresh; a
game takes the controllers back when it comes to the front.

The game modules are not in this repository and must never be: they come from
your own discs. Put them in `Modules/` (ignored by git), or build them in the
sibling checkouts; a build phase (`scripts/stage-games.sh`) copies and signs
them at the top of `PadHub.app`. A game without its module shows as not
installed.

| Game | Module | Built from |
|---|---|---|
| Super Mario Sunshine | `gGMSE01_recomp.dylib` | SunPad |
| Super Smash Bros. Melee | `gGALE01r2_recomp.dylib` and its `.dol-sha256` | MeleePad |

Switch games stay apps of their own for now, opened by URL scheme
(`nxnative-<title ID in lowercase>://`): nxnative builds each one as a whole
app around the game's code.

## Build

The games' sources come from sibling checkouts, each provisioned as its own
README explains (core libraries, `dev-config.plist`, MeleePad's Slippi
libraries):

```
switchApple/
  padhub/
  sunpad/              # branch nso-gamecube-controller
  meleepad/
  nso-gamecube-ios/
```

```sh
xcodegen generate
xcodebuild -scheme PadHub -configuration Release -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=<your team> PADHUB_BUNDLE_ID=<your bundle ID> -allowProvisioningUpdates build
```

or open `PadHub.xcodeproj`, set your team and `PADHUB_BUNDLE_ID`, and run the
Release configuration on a device (the emulators need the optimized build).
iOS 18 or later.

### Importing a disc

Put the disc image (`.iso`) in PadHub's Import folder: the Files app (On My
iPhone › PadHub › Import), the Finder's device window, or from a Mac:

```sh
xcrun devicectl device copy to --device <device> --domain-type appDataContainer \
  --domain-identifier <your bundle ID> --source "Super Mario Sunshine (USA).iso" \
  --destination "Documents/Import/Super Mario Sunshine (USA).iso"
```

PadHub recognizes the game by the ID at the start of the disc and hands the
disc to it the next time the game opens; the game imports it as its own
picker does, and the disc leaves the folder. Each game can also import a disc
from its own menu.

`padhub://open/<game>` opens a game, from Shortcuts for instance, and
`-padhubOpen <game>` at launch.

### Checking a build

- `-padhubSelfTest` opens each built-in game, goes back to the menu, and
  switches between them, 30 seconds each. Add `-meleepadAutoBoot` so Melee
  boots straight into the game rather than its own home screen.
- `-PadHubNSOControllers NO -SunPadNSOGCEnabled NO -MeleePadNSOGCEnabled NO`
  keeps Bluetooth off, so no permission prompt waits on the screen.
- PadHub writes `Documents/PadHub.log`; each game keeps its own log in
  `Library/Application Support/<SunPad|MeleePad>/Logs/runtime.log`.
- The Simulator works too, once each game's `scripts/ios-build-core.sh` has
  built its Simulator core and module: the games then read their data from
  the Mac's disk.
