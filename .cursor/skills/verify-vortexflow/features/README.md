# VortexFlow verification map

This directory is the maintained source for verifying user-facing VortexFlow behavior. Read this index before driving, then use the matching feature file as the recipe.

## Baseline preconditions

- Serve `site/` with `control-vortexflow serve` so the run has a `127.0.0.1` URL.
- Run `control-vortexflow doctor` and require a home title that contains `VortexFlow` and a working Chrome binary.
- Never launch `/Applications/Vortexflow.app` from a verification run.
- If doctor warns that the user's VortexFlow is running, skip native overlay recipes. Site recipes still run.
- Set `VERIFY_RUN_ID` so concurrent runs do not share `runs/` or `artifacts/`.

## Driving conventions

- Start every recipe from the served site unless its preconditions say otherwise.
- Prefer the handles in this map (ids, ARIA names, `data-*`) over CSS position or tab order.
- Treat every command as literal. Keep quoted names and flags unchanged.
- Run browser actions through `control-vortexflow` (`download-page`, `home-spiral`, `screenshot`, `fetch`).
- Native probe and visual preview are separate recipes. They do not substitute for a site path listed here.
- Do not delete proof artifacts during cleanup.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final screen.
- Site proof includes JSON from the recipe plus before/after screenshots with the page identity visible (H1 or `#gatekeeper`).
- Native proof includes `--probe` stdout or a visual-preview screenshot that shows `VortexFlow window switcher`.
- Record the feature ID and entry point with every artifact.
- Report an unreachable path with the attempted command and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with control-vortexflow`, `Gotchas`.

## Features

- [Home spiral](./home-spiral.md) covers the interactive overlay demo: pause the story, type a query, see the caption change.
- [Download and Gatekeeper](./download.md) covers getting the disk image and the Open Anyway steps.
- [Compare](./compare.md) covers the window-switcher matrix and competitor sections.
- [Theme](./theme.md) covers the light/dark toggle on the home page and inner pages.
- [Native overlay](./native-overlay.md) covers `--probe` and the isolated visual-preview bundle. Skip if the user's VortexFlow is already running.
