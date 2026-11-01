# PadHub

One app for the games you made from your own discs and cartridges on iPhone
and iPad: Super Mario Sunshine (SunPad), Super Smash Bros. Melee (MeleePad),
The Legend of Zelda: The Wind Waker (BlueWake), and the Switch games packed
with nxnative (Super Mario Bros. Wonder, Animal Crossing: New Horizons) all
run inside it.

- A carousel of the games' box art over a background that takes the selected
  game's colors, with a launch animation. The box art comes from
  [GameTDB](https://www.gametdb.com) the first time PadHub runs; a picture of
  your own replaces it (Settings).
- Browse and play with a controller: NSO GameCube controllers for the Switch 2
  through [NSOGCKit](https://github.com/pookee/nso-gamecube-ios) (iOS has no
  driver for them), or any controller iOS knows. Touch works too.
- Games start at once, without a title or settings screen of their own. A
  Switch game's settings (its launcher's) open from the hub (Game settings,
  or Y) and from PadHub's menu in the game; they apply the next time it starts.
- In any game, the NSO controller's HOME button (or PadHub Menu in the game's
  own menu, or the house button on a Switch game's touch controls) pauses it
  under PadHub's menu: Resume, Controllers (the controllers connected, their
  player, rumble one to find it, disconnect an NSO controller, the game's
  button mapping), Game settings, PadHub, Quit game. HOME again goes to the hub.
- A game left for the hub waits there, paused. A to resume it, Close game (or
  Quit game in PadHub's menu) to end it; starting another game asks to close
  the paused one first. Every game ends in-process, its memory freed, so any
  other game starts without PadHub restarting. Wind Waker starts once per
  launch of PadHub: starting it again after quitting it restarts PadHub.
- The hub turns with the phone, upright or sideways; each game keeps to its
  own orientation.

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
| The Legend of Zelda: The Wind Waker | `gGZLE01_recomp.dylib`, with `BlueWakeGame.framework` | BlueWake |
| Switch games | their code is their framework (`Switch<title ID>`) | nxnative |

### Switch games

nxnative prepares each Switch game as an Xcode project around the game's code
(`build_ipa_from_nsp.py --prepare-xcode`). PadHub builds that code and nxnative's
iOS host as a framework of its own per game (`Switch<title ID>`, with
`DM_EMBEDDED=1`), from the prepared project linked at `Switch/<title ID>`
(ignored by git, like everything made from your games):

```sh
ln -s "<your game folder>/<title ID>_build/xcode" Switch/<title ID>
```

The game files (`romfs.img`, several GB) and the shader libraries (`msl`) stay
out of the app: copy them once into PadHub's data container, from the app that
nxnative built for that game:

```sh
app="<your game folder>/<title ID>_build/xcode-derived-data/Build/Products/Release-iphoneos/DmIOS.app"
for item in romfs.img msl; do
  xcrun devicectl device copy to --device <device> --domain-type appDataContainer \
    --domain-identifier <your bundle ID> --source "$app/$item" \
    --destination "Library/Application Support/Switch/<title ID>/$item"
done
```

Each Switch game keeps its saves and its log (`log.txt`) in that folder too.
The Switch games need nxnative with this repository's patch (below) and iOS 26
or later; PadHub asks for the increased memory limit for them.

Quitting a Switch game stops it in-process (`dm_ios_stop` in the patch): its
threads end, its memory, files and Metal objects are freed, and the
framework's writable state goes back to the copy taken when it was loaded, so
its next start is a fresh boot. If anything cannot stop safely within a few
seconds, PadHub restarts instead.

## Build

PadHub builds the games from their own projects, checked out beside this one
at the commits below, with this repository's patches applied: they let each
game run inside a host app, add NSO GameCube controllers, and let the Switch
games stop in-process.

| Project | Upstream | Base commit | Patch |
|---|---|---|---|
| SunPad (Super Mario Sunshine) | [chrissotraidis/sunpad](https://github.com/chrissotraidis/sunpad) | `98b0439` | `patches/sunpad.patch` |
| MeleePad (Melee) | [chrissotraidis/meleepad](https://github.com/chrissotraidis/meleepad) | `65d655f` | `patches/meleepad/` |
| BlueWake (Wind Waker) | [chrissotraidis/bluewake](https://github.com/chrissotraidis/bluewake) | `92f29eb` | `patches/bluewake.patch` |
| nxnative (Switch games) | [seedds/nxnative](https://github.com/seedds/nxnative) | `5474c6f` | `patches/nxnative.patch` |
| NSOGCKit | [pookee/nso-gamecube-ios](https://github.com/pookee/nso-gamecube-ios) | `main` | |

```sh
git clone https://github.com/pookee/padhub
git clone https://github.com/pookee/nso-gamecube-ios
git clone https://github.com/chrissotraidis/sunpad
git -C sunpad checkout -b padhub 98b043920e1bb908dcdf366dec1706eca9b20cd6
git -C sunpad apply ../padhub/patches/sunpad.patch
git clone https://github.com/chrissotraidis/meleepad
git -C meleepad checkout -b padhub 65d655f3d1dba915410ae1b2ff42b667d85a5375
git -C meleepad am ../padhub/patches/meleepad/*.patch
git clone https://github.com/chrissotraidis/bluewake
git -C bluewake checkout -b padhub 92f29ebe6a2b6d0d400ada587341ba5230b35762
git -C bluewake apply ../padhub/patches/bluewake.patch
git clone https://github.com/seedds/nxnative
git -C nxnative checkout -b padhub 5474c6f34789a41770868564fbf4e9e32fc57584
git -C nxnative apply ../padhub/patches/nxnative.patch
```

Then make each game from your own copy, as its project's README explains:
SunPad's and MeleePad's core libraries, `dev-config.plist` and modules (and
MeleePad's Slippi libraries), BlueWake's builder for Wind Waker (below), and
nxnative's preparation for each Switch game (above). Nothing in these
repositories contains game code or data: modules, discs, keys and anything
built from them stay on your Mac and your devices. Do not share builds that
contain them.

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
  switches between them, 30 seconds each; then it quits each game that stops
  in-process from PadHub's menu and starts the first one again.
  `-padhubSelfTestGames wonder,acnh,sunpad` keeps it to those games.
- `-padhubOpen <game> -padhubGameMenuAfter <seconds>` brings up PadHub's menu
  over the game, and `-padhubGameMenuPage controllers` its controller page,
  for screenshots.
- `-PadHubNSOControllers NO -SunPadNSOGCEnabled NO -MeleePadNSOGCEnabled NO`
  keeps Bluetooth off, so no permission prompt waits on the screen.
- PadHub writes `Documents/PadHub.log`; each game keeps its own log in
  `Library/Application Support/<SunPad|MeleePad>/Logs/runtime.log`.
- The Simulator works too, once each game's `scripts/ios-build-core.sh` has
  built its Simulator core and module: the games then read their data from
  the Mac's disk.

## Wind Waker

BlueWake's builder makes the game module from your disc in the sibling
checkout (`scripts/builder/build.sh DISC.iso --out build/device`), then
`scripts/build-bluewake.sh com.your.bundle.id` builds `BlueWakeGame.framework`
from the same sources (`Games/BlueWake/BlueWakeGame.cmake`, included by a
small local change to BlueWake's `apple/ios/CMakeLists.txt`, with
`BLUEWAKE_PADHUB` in its entry and menu). PadHub's build phase copies the
framework, the module, `ModuleOptimizations` and the pipeline cache seed into
the app. The disc goes in `Documents/BlueWake/GZLE01.iso` (or the Import
folder); BlueWake prepares it the first time the game starts.

BlueWake's loop owns the main thread once it starts, so PadHub starts it from
a run-loop timer and its own screens run inside that loop. NSO GameCube
controllers reach the game as GameCube pads, by player. Quitting it ends the
loop as quitting the BlueWake app does (the memory card is written, the
renderer and audio shut down); PadHub waits for that before starting another
game. It does not start again in the same launch yet. The module and any build
containing it stay on your devices, as BlueWake's rules say.

## Credits

PadHub only hosts other people's work: [SunPad](https://github.com/chrissotraidis/sunpad),
[MeleePad](https://github.com/chrissotraidis/meleepad) and
[BlueWake](https://github.com/chrissotraidis/bluewake) by chrissotraidis and their
contributors (built on RecompCore, ModernGekko/Dolphin, Aurora, Dawn and SDL),
[nxnative](https://github.com/seedds/nxnative) by seedds, and box art from
[GameTDB](https://www.gametdb.com). NSO GameCube controllers go through
[NSOGCKit](https://github.com/pookee/nso-gamecube-ios). The patches in `patches/`
are under each project's own license.
