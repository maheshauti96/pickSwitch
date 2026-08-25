# PeekSwitch

A free, open-source window switcher for macOS, built for the mouse.

Press a button, see every window you have open, pick one. Works with any mouse and any
keyboard.

---

## The problems

**Cmd-Tab switches applications, not windows.** Six Chrome windows are one icon behind
one app. Picking the right one means switching to Chrome first, then hunting through
what it brings forward.

**Windows of the same app are impossible to tell apart.** Same icon, similar titles,
and a switcher that shows you neither. Three terminals and four editors look like the
same two entries repeated.

**Your hand has to leave the mouse.** You are already holding it. Reaching for a key
combination to move between windows is a gesture in the wrong direction, and the
keyboard shortcuts get worse the more windows you have.

**You lose track of what is actually open.** Windows spread across Spaces and monitors,
and nothing shows them in one place. Minimized windows disappear from view entirely.

**Getting to a browser tab is two searches.** Switch to the browser, then find the tab
among thirty others, in a strip of favicons too small to read.

**Opening something that is not running yet is a different gesture altogether.** You
try the switcher, the app is not there, so you stop and go to Spotlight instead.

**The good alternatives cost money or only switch apps.** The ones that switch windows
properly tend to be paid, closed, and quietly sending usage data somewhere.

---

## What PeekSwitch does about them

**Every window is its own card.** Four Finder windows are four cards, each with its own
title, its own thumbnail and its own place in the recency order. Minimized windows and
windows on other Spaces are included rather than hidden.

**Same-app windows are made distinguishable.** Each card takes a hint of colour from
its own icon, so a ring of windows is not a ring of identical white boxes. Browser
windows go further and show the icon of the site actually open in them, layered with
the browser's own icon — so three Chrome windows look like three different things,
because they are.

**Mouse-first, keyboard optional.** Hold a mouse button and the switcher appears next
to the cursor; scroll to choose, let go to switch. Your hand never moves. If you would
rather use the keyboard, a global shortcut does the same job, and PeekSwitch treats its
press and release exactly like a button's.

**Any mouse, any button.** Middle click works with no setup. For a side or thumb
button, press **Detect Button** and then press the button — no need to know its number.
PeekSwitch watches for buttons earlier in the pipeline than most mouse utilities, so
buttons that other apps cannot see usually still work here. For a button your mouse
keeps to itself, assign it to a keyboard shortcut and use that instead.

**Five ways to show it,** because a good arrangement for six windows is a bad one for
twenty: a horizontal strip, a grid, a list with a large preview, and two round
arrangements that fan the windows around your cursor. Each one can show live
screenshots or large icons.

**Real previews.** Thumbnails come from ScreenCaptureKit, so you see what is in a
window before committing to it. The selected one keeps refreshing.

**Recency that is per window, not per app.** The window you were just in is one flick
away, and the second card is preselected — so a quick hold-and-release means "back to
the last window".

**Type to narrow it down.** Start typing and the list filters by application and title.
It searches your open browser tabs too, so a tab is one gesture away instead of two.
Tab results are labelled by site — `x.com` rather than "Google Chrome", which every tab
would otherwise say — and carry the site's icon layered with the browser's.
Applications that are not running show up as well, so you can launch one without
leaving for Spotlight. If nothing matches, Return searches the web.

**Local and private.** No accounts, no telemetry, no analytics, no network calls —
except one, described plainly: to show the icon of a site open in your browser,
PeekSwitch fetches that icon from that site's own address, with no cookies and nothing
identifying, and never for a private browsing window.

---

## Download

**[Download PeekSwitch 1.0.0 (.dmg)](https://github.com/maheshauti96/pickSwitch/releases/latest/download/PeekSwitch-1.0.0.dmg)** —
2 MB, universal (Apple Silicon and Intel), macOS 15 or newer.

All releases are on the [releases page](https://github.com/maheshauti96/pickSwitch/releases).

### Installing

1. Open the disk image and drag **PeekSwitch** to your Applications folder.
2. Open it. macOS will refuse, and say the developer cannot be verified. This is
   expected — keep going.
3. Open **System Settings → Privacy & Security**, scroll down to the **Security**
   section, and click **Open Anyway** next to PeekSwitch. Authenticate when asked.
4. Grant the permissions it asks for. The setup window explains what each one buys you.

You only do this once; macOS then remembers PeekSwitch as an exception, as described in
[Apple's own documentation](https://support.apple.com/en-us/guide/mac-help/mh40616/mac).

The reason is worth stating plainly rather than hiding: PeekSwitch is signed, but it is
not *notarized*, because notarizing requires a paid Apple Developer account. macOS
blocks unnotarized downloads, and the wording it uses — "cannot be verified" — reads as
though the app is broken rather than simply unregistered.

Note that on macOS 15 and later, right-clicking the app and choosing Open no longer
works as a shortcut for this; Apple removed that bypass, so the Privacy & Security route
above is the only one. Older instructions elsewhere on the internet still describe the
right-click trick.

If you would rather not take our word for any of it, building from source takes about a
minute and produces a copy signed on your own machine — see
[Building from source](#building-from-source).

---

## Requirements

- macOS 15 (Sequoia) or newer
- Any Mac, Apple Silicon or Intel
- Any mouse with at least a middle click, or just the keyboard

---

## Permissions

PeekSwitch asks for three permissions and explains each one on first launch. It runs
with any subset of them and tells you what you are missing rather than failing quietly.

| Permission | What it buys you | Without it |
| --- | --- | --- |
| **Input Monitoring** | Noticing your mouse button | Keyboard shortcut only |
| **Accessibility** | Listing individual windows, and raising the exact one you pick | Whole apps come forward instead of specific windows |
| **Screen Recording** | Window thumbnails | Cards show large app icons instead |

Automation permission is asked for separately, the first time it looks at browser
windows, and only powers tab search and site icons.

You can reopen the setup window at any time from the menu bar icon.

---

## Using it

By default PeekSwitch works out what you meant from how long you held the button.

**Hold** it and the switcher tracks your hand: scroll to move the selection, release to
switch. Fast, once you know where you are going.

**Tap** it and the switcher stays up so you can read the titles and decide. Click a
card, or tap again, to switch.

| Action | Result |
| --- | --- |
| Hold the trigger button | Switcher appears by the cursor and follows the hold |
| Scroll | Move the selection, wrapping at both ends |
| Move onto a card | Select it |
| Release after holding | Switch to the selected window |
| Quick tap | Switcher stays open for browsing |
| Tap again while open | Switch to the selected window |
| Click a card | Switch to it |
| Keyboard shortcut | Open it, and press again to close it |
| Arrow keys | Move the selection — a grid moves by a row, everything else by one window |
| Return | Switch to the selected window |
| Start typing | Filter by app, title, browser tab or installed app |
| Escape, or click outside | Close without switching |

Once it is open you can finish the job entirely from the keyboard — arrows to choose,
Return to switch — or entirely from the mouse. Neither is the "real" way.

---

## Settings

- **Trigger button** — middle, side back, side forward, or **Detect Button** to use
  whatever you press next.
- **Behaviour** — automatic (tap keeps it open, hold switches on release), or force
  hold or toggle if you would rather it never guessed.
- **Keyboard shortcut** — pick one, or record your own. Settings tells you whether the
  shortcut has actually fired, which matters more than it sounds: macOS reports a
  shortcut as registered even when another app has already claimed it, and then the
  keystroke simply never arrives. If it says the shortcut has not been seen after you
  press it, something else owns it — pick another.
- **Arrangement** — strip, grid, list, circular or spiral.
- **Each window shows** — a live preview, or a large icon.
- **Tint each window by its icon** — on by default. Turns itself off when you have
  macOS's Increase Contrast enabled.
- **Windows to show** — 5 to 25.
- **Include the switcher in screenshots** — worth turning off while presenting, since
  the switcher lists the title of every window you have open.
- **Permissions** — live status, with links into System Settings.

### A note on the middle button

PeekSwitch has to *consume* whichever button triggers it, or the click would also land
in whatever is under the cursor. With the default middle button, that means
middle-clicking a link to open it in a new tab stops working while PeekSwitch is
running. Settings warns about this. Moving to a side button avoids it — press **Detect
Button** and then that button.

---

## Building from source

```sh
git clone https://github.com/maheshauti96/pickSwitch.git peekswitch
cd peekswitch
Scripts/create-signing-certificate.sh   # once
Scripts/build-app.sh --install
open /Applications/PeekSwitch.app
```

Command Line Tools is enough — Xcode is not required.

```sh
Scripts/build-app.sh --debug         # debug configuration
Scripts/build-app.sh --native-arch   # skip the universal build
Scripts/make-dmg.sh                  # package a disk image
swift test                           # 402 tests
```

### Run the signing script first

It matters more than it looks. macOS records privacy permissions against an app's
**code identity**, not its name or its path. An ad-hoc signature derives that identity
from the binary's own hash, so it changes on every build, and two things follow:

- You have to grant permissions again after every rebuild.
- Stale records pile up under the same bundle identifier until macOS refuses to add the
  app to the privacy lists at all — you click `+`, and the row never appears, with no
  error to explain it.

`create-signing-certificate.sh` makes a self-signed certificate called `PeekSwitch Dev`
in your login keychain, and `build-app.sh` uses it automatically. The identity then
names the certificate rather than the binary, which is stable across rebuilds.

The certificate shows as untrusted in `security find-identity -v`. That is expected:
trust governs *verifying* signatures, not making them, and `codesign` is happy to sign
with it.

To use your own identity instead:

```sh
PEEKSWITCH_SIGN_IDENTITY="Developer ID Application: You (TEAMID)" Scripts/build-app.sh
```

### If PeekSwitch will not appear in a privacy list

Almost always leftover records from a build with a different identity:

```sh
tccutil reset All dev.peekswitch.PeekSwitch    # no sudo needed
Scripts/build-app.sh --install
```

Then grant permissions from PeekSwitch's own setup window rather than the `+` button —
the app asks the system directly, which is more reliable than adding it by hand. Check
what it sees with:

```sh
/Applications/PeekSwitch.app/Contents/MacOS/PeekSwitch --probe
```

Run it from `/Applications` rather than `build/`. The build directory is replaced on
every build, and a privacy grant pointing at a path that no longer exists is dead
weight.

---

## How it works

```
Sources/PeekSwitchCore/
  Models/   WindowEntry, layouts, SelectionMath, IconTint, TriggerButton, KeyResponse
  Core/     WindowRegistry, MRUTracker, TriggerMonitor, HotKeyMonitor, ThumbnailService,
            BrowserTabService, BrowserFaviconService, ApplicationCatalog,
            ActivationService, PermissionsManager, SettingsStore, SwitcherController
  UI/       OverlayPanel, OverlayView, the card and wedge views, MenuBarController,
            OnboardingView, SettingsView
```

A few decisions worth knowing before changing things.

**Window enumeration combines two APIs.** Accessibility supplies the window set — it is
the only one that sees minimized windows and the only one that can raise a specific
window. CGWindowList supplies front-to-back order and window IDs. They are stitched
together with `_AXUIElementGetWindow`, resolved at runtime because it is in no public
header. Matching on title and frame instead breaks on exactly the cases that matter:
several same-titled windows in one app, and tiled windows that share a frame.

**The event tap is installed at the HID level,** ahead of session-level taps. Mouse
utilities install their own tap at the session level and consume the extra buttons
there, so a session-level tap never sees them. This is why buttons that appear
undetectable to other apps often work here.

**Presentation stays under 150 ms because thumbnails are not on the critical path.** The
panel goes up showing icons, and captures land underneath as they finish. The panel and
its hosting view are built once at launch, not per presentation.

**Hover is polled, not tracked.** The overlay is a non-activating panel that never
becomes key, which makes AppKit's mouse tracking unreliable for it — especially while a
button is physically held down, as it always is in hold mode. The controller samples the
cursor at 60 Hz and hit-tests using the same arithmetic that drew the cards, so what is
drawn and what is clickable cannot disagree.

**Activation order is deliberate:** unhide the app, unminimize the window, raise the
window, *then* activate the app. Activating before raising produces a visible flicker as
the app's previously frontmost window appears and is immediately replaced.

---

## Not there yet

- Notarized distribution and Homebrew (right-click to open is the workaround for now)
- Recency history that survives a restart
- Excluding specific apps, and pinning favourites
- Customising size, opacity and animation speed
- Full VoiceOver support

---

## Credits

Inspired by [Dory – App Switcher](https://apps.apple.com/app/dory-app-switcher/id6446071638)
by Segev Sherry, and by the window-preview work in
[alt-tab-macos](https://github.com/lwouis/alt-tab-macos) and
[DockDoor](https://github.com/ejbills/DockDoor).

## License

MIT. See [LICENSE](LICENSE).
