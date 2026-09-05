# VortexFlow — approved spiral identity

The user selected the first spiral concept and approved its teal, mint and violet refinement on 5 September 2026. The approved presentation is retained in `source/approved-spiral-color.png`.

## Source of truth

- `png/vortexflow-mark-1024.png`: isolated three-color spiral, genuine alpha transparency.
- `png/app-icon-1024.png`: dark rounded-square Mac icon, genuine transparent exterior.

These masters were extracted with the built-in ImageGen tool from the approved presentation. The mark extraction preserves the three curved sections and assigns teal to the upper section, violet to the right and mint to the lower-left. The app-icon extraction preserves the approved dark tile. Two intermediate exports with a baked checkerboard were rejected and are not used.

The successful prompts and size-normalization notes are recorded in [source/prompts.md](source/prompts.md).

The nominal palette is teal `#159DB3`, mint `#31B58E` and violet `#8A7BF2`. The PNG artwork retains the approved visual color treatment. Do not hand-redraw the logo or substitute a generic spiral.

## Regenerate exports

Run from the repository root on macOS:

```sh
bash Scripts/generate-icons.sh
```

`Scripts/export-brand.swift` mechanically resizes and packages the real approved artwork. It produces PNGs, a three-size ICO, lockups, monochrome variants and the sharing image. SVG paths remain available for compatibility, but they embed PNG artwork; they are not editable vector outlines. The wordmark is typeset in the site's native system sans serif. A manually refined vector master can be added later without changing consumer URLs.

The same command creates `Resources/AppIcon.icns` and the native `VortexflowMark.png` / `MenuBarMark` @1x/@2x/@3x resources. They serve the Finder icon, menu bar, Settings, onboarding and menu header. No behavior or permission settings need to change.

For an already-installed certificate-signed local development build, `bash Scripts/refresh-installed-brand.sh --apply` refreshes only its five brand resources. It verifies that both architecture instruction fingerprints and the signing requirement remain unchanged, archives the original bundle as a ZIP in `build/brand-backups/`, and stops the utility for replacement. Reopen it after the update. This avoids accidentally installing an older executable from a website-only branch.

The generator requires macOS's image services. In a restricted sandbox, `iconutil` can report “Invalid Iconset” even when all ten PNG sizes are correct; run the packaging command with the required local permission, rather than changing the artwork.

## Use

- Color mark: website header/footer, browser favicon and native menu bar.
- Dark app icon: macOS application bundle and website app-icon/download surface.
- Single-color mark: contexts where full color is unavailable.
- Use the normal system-font product name next to the mark; do not stretch either asset.
- Refresh an installed application's resources only on the intended binary revision. Preserve its stable signing identity and settings; branding must not roll back an unrelated fix.
