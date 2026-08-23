# PeekSwitch

A free, open-source macOS window switcher built for the mouse.

Hold an extra button on your mouse, and a strip of your recent **windows** appears
next to the cursor, each one showing a live thumbnail of its contents. Roll the
wheel to pick one, let go to switch. Your hand never leaves the mouse and your
fingers never touch the keyboard.

Built for the Logitech MX Master 3, works with any mouse that has a middle click or
thumb buttons.

## What makes it different

Most switchers, including the commercial ones this was modelled on, switch between
*applications*. PeekSwitch switches between *windows*:

- **Every window is its own card**, with its own thumbnail and its own
  most-recently-used timestamp. Four Finder windows are four cards, not one.
- **Real previews.** Thumbnails come from ScreenCaptureKit, so you see what is
  actually in the window before you commit to it. The selected card refreshes live.
- **Most-recently-used order**, per window. The window you were just in is always
  one flick away.
- **Mouse-first.** Hold to reveal, scroll or hover to choose, release to switch.
  The keyboard is optional, not the primary path.
- **Local and private.** No network calls, no telemetry, no analytics. Three
  permissions, all of them load-bearing.

## Requirements

- macOS 15 (Sequoia) or newer
- Apple Silicon or Intel (ships as a universal binary)
- Swift 6 toolchain to build (Command Line Tools is enough — Xcode is not required)

## Building

```sh
git clone <your-fork-url> peekswitch
cd peekswitch
Scripts/create-signing-certificate.sh   # once, so permissions survive rebuilds
Scripts/build-app.sh --install
open /Applications/PeekSwitch.app
```

`Scripts/build-app.sh` compiles the package and wraps it into `PeekSwitch.app`. The
bundle matters: macOS attaches permission grants to a bundle identity, and
`LSUIElement` (which keeps PeekSwitch out of the Dock and Cmd-Tab) lives in
`Info.plist`. Running the bare SwiftPM executable will not behave correctly.

Run `Scripts/create-signing-certificate.sh` once first. Without a stable signing
identity, macOS forgets PeekSwitch's permissions on every rebuild and can end up
refusing to list it at all — see [Signing](#signing-and-why-it-decides-whether-permissions-work-at-all).

Options:

```sh
Scripts/build-app.sh --install       # also replace /Applications/PeekSwitch.app
Scripts/build-app.sh --debug         # debug configuration
Scripts/build-app.sh --native-arch   # skip the universal build, build for this Mac only
```

Tests:

```sh
swift test
```

## Permissions

PeekSwitch asks for three permissions on first launch and explains each one in the
setup window. It works with any subset of them and tells you what you are missing.

| Permission | What it buys you | Without it |
| --- | --- | --- |
| **Input Monitoring** | Noticing your extra mouse button | Keyboard shortcut only |
| **Accessibility** | Listing individual windows and raising the exact one you pick | Whole apps come forward instead of specific windows |
| **Screen Recording** | Window thumbnails | Cards show app icons |

You can reopen the setup window any time from the menu bar item.

### Signing, and why it decides whether permissions work at all

Run this once, before anything else:

```sh
Scripts/create-signing-certificate.sh
```

macOS records privacy permissions against an app's **code identity**, not its path or
its name. An ad-hoc signature (`codesign --sign -`) derives that identity from the
binary's own hash, so it changes on every single build. Two things follow, and the
second one is nasty:

- Permissions have to be granted again after every rebuild.
- Stale records accumulate under the same bundle identifier. Once they conflict with
  what is on disk, macOS stops adding the app to the privacy lists altogether — you
  pick it with the `+` button and the row simply never appears, with no error.

`create-signing-certificate.sh` generates a self-signed code-signing certificate
called `PeekSwitch Dev` in your login keychain, and `build-app.sh` picks it up
automatically. The designated requirement then names the certificate instead of the
binary:

```
identifier "dev.peekswitch.PeekSwitch" and certificate root = H"78272f59…"
```

That is stable across rebuilds, so a grant given once keeps working. `build-app.sh`
prints the requirement on every build if you want to confirm it is not changing.

The certificate shows up as untrusted (`CSSMERR_TP_NOT_TRUSTED`) in
`security find-identity -v`. That is expected and harmless: trust governs *verifying*
signatures, not producing them, and `codesign` signs with it happily. Making it
trusted would mean a system-wide keychain change for no benefit.

To use your own identity instead:

```sh
PEEKSWITCH_SIGN_IDENTITY="Developer ID Application: You (TEAMID)" Scripts/build-app.sh
```

### If PeekSwitch will not appear in a privacy list

Almost always leftover records from an earlier build with a different identity. Clear
just this app's records and reinstall:

```sh
tccutil reset All dev.peekswitch.PeekSwitch    # no sudo needed
Scripts/build-app.sh --install
open /Applications/PeekSwitch.app
```

Then grant the permissions from PeekSwitch's own setup window rather than the `+`
button — the app asks the system directly, which is more reliable than adding it by
hand. Confirm with:

```sh
/Applications/PeekSwitch.app/Contents/MacOS/PeekSwitch --probe
```

Two things that also matter:

- **Quit PeekSwitch before replacing the bundle.** `--install` does this for you.
  Swapping a bundle out from under a running process leaves macOS holding the old
  identity.
- **Run it from `/Applications`, not from `build/`.** `build/` gets deleted on every
  rebuild, and a privacy entry pointing at a path that no longer exists is dead
  weight.

## Setting up an MX Master

The wheel click works with no setup. For a thumb or Gesture button, try
**Detect Button…** in Settings first and press it.

PeekSwitch installs its event tap at the **HID level** rather than the session level,
which matters here. Mouse software like Logi Options+ runs its own session-level event
tap and consumes the extra buttons there, so anything else watching at session level
never sees them. A HID-level tap sits earlier in the pipeline and gets the button
first. This is why other apps can use these buttons, and PeekSwitch initially could
not.

Check which level yours ended up at:

```sh
/Applications/PeekSwitch.app/Contents/MacOS/PeekSwitch --probe
```

Look for `trigger tap installed at: HID level`.

### The thumb / Gesture button, and why Detect can't see it

Measured on an MX Master 3 (vendor `0x46d`, product `0xb023`) by logging its raw HID
input. With the thumb button set to **"Do Nothing"** in Logi Options+, the mouse reports
exactly three button usages:

| HID usage | Button |
| --- | --- |
| 1 | Left |
| 2 | Right |
| 3 | Middle (wheel click) |

That is the complete list. The thumb button produces **no HID input on any usage page,
from any device interface** — nothing to intercept, at any event tap level. Options+
discards it inside its own driver rather than passing it on.

So this is not something PeekSwitch can fix. Route it through the keyboard instead:

1. Logi Options+ → your mouse → assign the button to **"Keyboard shortcut"**
2. Record **F13**. No Mac keyboard binds F13 by default, so nothing will fight it.
3. PeekSwitch Settings → Keyboard shortcut → **F13**

PeekSwitch handles the shortcut's press *and* release, so a button mapped this way
behaves exactly like a real mouse button: tap to keep the strip open, hold and release
to switch. Nothing is lost by going through a keystroke.

Avoid **"Do Nothing"** — that is the one setting that reliably gets you nothing, since
Options+ discards the press rather than passing it on.

## Using it

There are two ways to drive it, and by default PeekSwitch works out which one you
meant from how long you held the button.

**Hold** the trigger button and the strip tracks your hand: scroll to move the
selection, release to switch. Fast, once you know where you're going.

**Tap** it and the strip stays up so you can read the window titles and decide. Click
a card, or tap the button again, to switch.

| Action | Result |
| --- | --- |
| Hold the trigger button | Strip appears next to the cursor and follows the hold |
| Scroll / thumb wheel | Move the selection, wrapping at both ends |
| Move onto a card | Select that card |
| Release after holding | Switch to the selected window |
| Quick tap | Strip stays open for browsing |
| Tap again while open | Switch to the selected window |
| Click a card | Switch to it |
| Keyboard shortcut | Open the strip and keep it open |
| Escape, or click outside | Close without switching |

The second card is preselected rather than the first, because the first card is the
window you are already looking at. Combined with hold mode, that makes a quick
hold-and-release a "go back to the last window" gesture.

## Settings

- **Trigger button.** Middle, thumb back, thumb forward, or **Detect Button…**, which
  assigns whatever button you press next. Use that for a Gesture button or any extra
  button that isn't in the list — there is no need to know its number.
- **Activation.** Automatic (tap keeps it open, hold switches on release), or force
  Hold or Toggle if you'd rather it never guess.
- **Keyboard shortcut.** Pick from a short list. Settings tells you whether the
  shortcut has actually fired, which matters — see below.
- **Windows to show.** 5–25.
- **Permissions.** Live status with links into System Settings.

### If the keyboard shortcut does nothing

`RegisterEventHotKey` returns success even when another app already owns the
combination — the keystroke just never arrives. So "registered" in the log proves
nothing. Settings shows **"This shortcut is working"** only once the shortcut has
genuinely fired; if it still says "Not seen yet" after you press it, something else
has claimed it. Pick another from the list. **F13** has no stock binding on any Mac
keyboard and is the reliable fallback.

### A note on the middle button

PeekSwitch has to *consume* its trigger button, otherwise the click would also land in
whatever is under the cursor. With the default middle button that means middle-click to
open a link in a new tab stops working in browsers. Settings warns about this.

To move off the middle button, try **Detect Button…** in Settings and press the button
you want. If nothing is detected, that button is being consumed by Logi Options+ or a
similar tool — see [Setting up an MX Master](#setting-up-an-mx-master) for the keyboard
shortcut route, which works for buttons that can't be detected directly.

## How it works

```
Sources/PeekSwitchCore/
  Models/       WindowEntry, StripLayout, SelectionMath, OverlayPlacement,
                TriggerButton, Authorization
  Core/         WindowRegistry, MRUTracker, TriggerMonitor, HotKeyMonitor,
                ThumbnailService, ActivationService, PermissionsManager,
                SettingsStore, SwitcherController
  UI/           OverlayPanel, OverlayView, WindowCardView, MenuBarController,
                OnboardingView, SettingsView
  App/          AppDelegate
Sources/PeekSwitch/
  main.swift    NSApplication bootstrap
```

A few decisions worth knowing about before changing things:

**Window enumeration combines two APIs.** Accessibility supplies the window set (it
is the only one that sees minimized windows and the only one that can raise a
specific window); CGWindowList supplies front-to-back order and CGWindowIDs. They
are stitched together with `_AXUIElementGetWindow`, resolved at runtime via `dlsym`
because it is not in any public header. Matching on title plus frame instead breaks
on exactly the cases that matter: several same-titled windows in one app, and
windows that share a frame because they are tiled.

**There are two event taps, not one.** A persistent one watching only
`otherMouseDown`/`otherMouseUp`, and a second one for scroll and key events that is
created disabled and toggled with `CGEvent.tapEnable` while the overlay is open. A
tap's event mask is fixed at creation, so the alternative would be recreating a tap
on every presentation — right on the latency path. The tap callback does nothing but
read one integer and hop to the main queue; anything slower and macOS disables the
tap out from under you, which is why there is also a re-arm path.

**Presentation is under 150 ms because thumbnails are not on the critical path.**
The panel goes up showing app icons and captures land underneath as they finish. The
panel and its hosting view are built once at launch, not per presentation.

**Hover is polled, not tracked.** The overlay is a non-activating panel that never
becomes key, which makes AppKit's mouse tracking unreliable for it — especially
while a mouse button is physically held down, as it always is in hold mode. Instead
the controller samples the cursor at 60 Hz while the overlay is open and hit-tests
using the same `StripLayout` arithmetic that drew the cards. That shared arithmetic
is why the strip does its own layout rather than using a `ScrollView`: a
`ScrollView`'s offset is not observable, so drawing and hit-testing would be free to
disagree.

**Activation order is deliberate:** unhide the app, unminimize the window, raise the
window, *then* activate the app. Activating before raising produces a visible
flicker as the app's previously frontmost window appears and is then replaced.

### Toolchain notes

Two quirks if you build with Command Line Tools rather than Xcode, both handled in
`Package.swift`:

- SwiftUI's `@State` is a macro now, and its plugin ships only with Xcode. The
  codebase uses `ObservableObject` view models instead, which is the better home for
  this state anyway.
- swift-testing's macro plugin sits in a subdirectory the compiler does not scan
  automatically, and its runtime is not on the default library search path.
  `Package.swift` detects both and adds the flags only when needed, so an Xcode
  toolchain is unaffected.

## Not in version 1

Scoped out on purpose, roughly in the order they are worth adding:

- Radial/fan, grid and list-plus-preview layouts (the horizontal strip is the only
  one)
- Type-to-filter and fuzzy search
- Launching applications that are not running
- App exclude lists and pinned favourites
- Customising size, opacity and animation speed
- An arbitrary keyboard shortcut (a short preset list is offered instead of a recorder)
- Persisting MRU history across launches
- Browser tab switching
- Full VoiceOver support
- Homebrew and notarized installer packaging

## Credits

Inspired by [Dory – App Switcher](https://apps.apple.com/app/dory-app-switcher/id6446071638)
by Segev Sherry, and by the window-preview work in
[alt-tab-macos](https://github.com/lwouis/alt-tab-macos) and
[DockDoor](https://github.com/ejbills/DockDoor).

## License

MIT. See [LICENSE](LICENSE).
