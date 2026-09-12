# Theme

The site has a light theme and a dark theme. The toggle in the header switches `html[data-theme]` and the spiral demo follows it.

## Sub-features

- `theme-toggle` is a button `[data-theme-toggle]` whose `aria-label` is `Switch to the dark theme` or `Switch to the light theme`.
- `theme-persist` stores `vf-theme` in `localStorage` when the choice differs from the system.
- `theme-demo` updates the home spiral appearance with the same theme.

## How to get to it (user POV)

- Choose the sun/moon button in the header on any page that includes `site.js`.
- On home, the demo also has Light/Dark buttons (`[data-appearance-choice]`). Those are the same switch as the header.

## Driving it with control-vortexflow

Preconditions:

- `control-vortexflow serve` has a URL.
- `control-vortexflow doctor` passed.

- **Read initial state.** Run `control-vortexflow screenshot / $ART/theme-before.png`.
- **Toggle.** There is no one-shot recipe; evaluate through Chrome via `node .cursor/skills/verify-vortexflow/scripts/drive-site.cjs eval "$(cat runs/$VERIFY_RUN_ID/url)/" "document.querySelector('[data-theme-toggle]').click(); document.documentElement.dataset.theme"`.
- **Confirm.** The evaluate result is `dark` or `light` and is the opposite of the first screenshot's theme. Take `$ART/theme-after.png` with `control-vortexflow screenshot / $ART/theme-after.png`.
- **Proof.** Both screenshots plus the evaluate result. A CSS-only check of `site.css` is not proof.

## Gotchas

- Headless Chrome has no OS appearance. The inline head script falls back to `light` unless `localStorage` is set. Do not assume dark is the default.
- Clicking a demo Light/Dark button also sets the page theme. Do not treat them as a second, independent store.
- Inner pages share `site.js`. Proving home is not proving `/privacy/` unless you toggle there too.
