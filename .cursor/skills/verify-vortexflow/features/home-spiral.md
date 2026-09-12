# Home spiral

The home page shows an interactive VortexFlow spiral. A visitor can pause the story, type into the overlay, and see windows narrow to a match without leaving the page.

## Sub-features

- `spiral-visible` shows the demo figure and the H1 `Don't leave the pointer`.
- `spiral-search-button` pauses the timed story via `Search`.
- `spiral-type` types into the shadow-root search field and updates the caption.

## How to get to it (user POV)

- Open `/` and look at the hero. The spiral is in `#product-demo`.
- Choose the `Search` button under the spiral.
- Type in the overlay search field (`aria-label="Search the example spiral"`).
- Choose a demo chapter (`Windows`, `Find a tab`, `Search & ask`, `Pinned favorites`).

## Driving it with control-vortexflow

Preconditions:

- `control-vortexflow serve` has a URL.
- `control-vortexflow doctor` passed.
- Chrome is available.

- **Open home.** Run `control-vortexflow fetch /`. The HTML contains `id="hero-h"` and `id="product-demo"`.
- **Drive search.** Run `control-vortexflow home-spiral`. The command writes `artifacts/$VERIFY_RUN_ID/home-spiral.json`, `home-before.png`, and `home-search.png`.
- **Confirm identity.** `ready.title` contains `VortexFlow` and `ready.h1` contains `Don't leave the pointer`.
- **Confirm action.** `typed.ok` is `true` and `typed.value` is `snowfl`. `home-search.png` shows the spiral after the query, not a blank hero.
- **Proof.** Keep those three files. A screenshot of the untouched home page is not enough.

## Gotchas

- The timed story steals focus if you never click `Search` or the spiral. The recipe clicks `#story-search` first.
- The search field lives in `#hero-spiral`'s shadow root. A page-level `input` selector misses it.
- `snowfl` is the demo's Snowflake tab. A random string may produce only web-search offers; still valid if `typed.ok` is true, but the screenshot will not show a Snowflake card.
- Reduced-motion in the OS does not skip this recipe. The demo has its own checkbox.
