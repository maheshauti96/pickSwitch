# Compare

The compare page states VortexFlow against Cmd-Tab, AltTab, DockDoor, Dory, and others, with a feature table and prose for each.

## Sub-features

- `compare-title` names VortexFlow against Cmd-Tab, Dory, AltTab.
- `compare-table` has a Feature column and a VortexFlow column marked `class="us"`.
- `compare-prose` has sections for Cmd-Tab, Dory, AltTab, BetterCmdTab, DockDoor, and the keyboard-first group.

## How to get to it (user POV)

- Choose `Compare` in the header.
- Go to `/compare/`.
- Follow the footer `Compare` link.

## Driving it with control-vortexflow

Preconditions:

- `control-vortexflow serve` has a URL.
- `control-vortexflow doctor` passed.

- **Open compare.** Run `control-vortexflow fetch /compare/`. The HTML contains `<table class="compare">` and `VortexFlow vs Cmd-Tab`.
- **Screenshot.** Run `control-vortexflow screenshot /compare/ $ART/compare.png` with `$ART` set to `artifacts/$VERIFY_RUN_ID`.
- **Confirm table.** The fetched HTML includes `scope="row">Opens at the pointer` and `Yes · any button` in a `td` with class `us`.
- **Proof.** Keep the HTML excerpt (save fetch stdout to `$ART/compare.html`) and `compare.png` showing the H1 `A spiral at the pointer, not another Cmd-Tab.`

## Gotchas

- Header `Compare` is missing on the home page below the menu breakpoint; `/compare/` still works.
- Empty competitor cells say `No`, not an em dash.
- Do not treat a GitHub README comparison as this page.
