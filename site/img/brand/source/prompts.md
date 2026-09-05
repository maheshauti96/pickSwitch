# Approved logo asset generation

Mode: built-in ImageGen. No CLI/API fallback was used. These are the successful production-asset prompts, applied to the approved color presentation in this directory. Intermediate opaque/checkerboard app-icon results were rejected.

## Transparent mark

Production asset extraction from the approved image. Extract ONLY the large three-color VortexFlow spiral mark from the top center. Keep its exact shape, proportions, asymmetry, orientation, three separate curved sections, sharp inward tips, smooth rounded outward corners, center negative space, and precise teal upper / violet right / mint lower-left color placement unchanged. This is the final approved logo, not a redesign.

Output a single 1024 x 1024 RGBA PNG on a genuinely TRANSPARENT alpha background. No white, off-white, black or checkerboard background pixels. Center the mark optically, with its height occupying about 90% of the square and its original width-to-height ratio unchanged. Preserve the clean, flat color appearance of the approved mark, crisp anti-aliased edges and transparent gaps, without light halos. Remove the wordmark, app tile, tiny monochrome example, and all other content. No letters, shadows, textures, new gradients, outlines, mockups or extra imagery. Only the exact approved color spiral isolated on transparency.

## Mac app icon

Extract the small black rounded-square VortexFlow app icon from the lower left of this approved design. Keep the entire black tile and its teal, violet and green spiral. Enlarge it faithfully into a single square icon asset. Transparent background, transparent PNG output. Nothing outside the icon. No text. No presentation sheet. No pattern or scene. Preserve the exact icon design and original colors.

## Export normalization

The successful tool outputs were 1254 × 1254 PNGs despite the requested size. Their genuine alpha was checked and they were proportionally resized to the committed 1024 × 1024 masters with macOS sips. All smaller site/native exports are produced by Scripts/generate-icons.sh from those masters. The logo is not redrawn by the export pipeline.
