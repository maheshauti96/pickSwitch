# Native overlay

The Mac app shows a spiral of windows around the pointer. Verification of that overlay is isolated from the user's installed copy.

## Sub-features

- `probe` prints permissions, window counts, and tap placement, then exits without showing the overlay.
- `visual-preview` opens the real overlay chrome on synthetic windows, bundle id `io.vortexflow.VisualPreview`.
- `live-switcher` is the installed app. Skip it when `/Applications/Vortexflow.app` is already running.

## How to get to it (user POV)

- Launch VortexFlow from Applications, then middle-click or press Control-Option-Space.
- Open Settings from the menu bar icon.
- For an agent: `native-probe` or `native-preview` from `control-vortexflow`.

## Driving it with control-vortexflow

Preconditions:

- `Scripts/build-app.sh --native-arch --debug` has produced `build/Vortexflow.app`, or `Scripts/build-visual-preview.sh` has produced `build/VortexflowVisualPreview.app`.
- `control-vortexflow doctor` did not warn that the user's VortexFlow is running, except for `visual-preview`, which is a different bundle.

- **Probe.** Run `control-vortexflow native-probe`. Stdout starts with `VortexFlow` and contains a `Permissions` section. Save it to `artifacts/$VERIFY_RUN_ID/probe.txt`. Exit code `0`. The overlay does not appear.
- **Visual preview.** Run `control-vortexflow native-preview`. Screenshot with `screencapture -l <windowid>` or a full-display capture cropped to the preview. The overlay accessibility name is `VortexFlow window switcher`. Quit with `osascript -e 'tell application "VortexFlow Visual Preview" to quit'`.
- **Live switcher.** Only if no VortexFlow process is bound to `/Applications/Vortexflow.app`. Open `build/Vortexflow.app`, press the shortcut, screenshot. Do not write the user's `~/Library/Preferences/io.vortexflow.Vortexflow.plist`.
- **Proof.** `probe.txt` for probe. A screenshot that includes the spiral and the accessibility name for preview. A site spiral screenshot does not prove this feature.

## Gotchas

- Two apps share nothing useful: visual preview does not install event taps and does not write settings. The live app does both, against the user's defaults domain.
- `--probe` can report the terminal's Screen Recording status, not the app's. Read the caveat in its stdout.
- `killall Vortexflow` would kill the user's switcher. Never do that from cleanup.
- Building with `--install` replaces `/Applications/Vortexflow.app`. Verification does not run that flag.
