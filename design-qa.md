# VortexFlow website glass-showcase QA

final result: passed

Reviewed 6 September 2026. Scope: bring the approved Mac widget's glass treatment and hub motion into the existing website. Previous native-build QA is preserved at [previous-native-qa.md](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/previous-native-qa.md).

## Outcome

All four live radial examples now share the glass renderer: hero, pinned shortcuts, window actions and the layout explorer. Light/Dark controls change the examples without changing the website's paper-and-green theme. The center uses the native breathing/ripple equations; captions and hit targets remain stationary. The existing automatic walkthrough, manual search, keyboard selection, pins and window actions remain functional.

No actionable P0/P1/P2 finding remains in this scoped showcase update. The website remains an explicitly labeled interactive demo with fictional windows, not a recording of the user's desktop. Its existing copy, logo, pricing and coming-soon purchase/trial status are preserved.

## Source and comparison evidence

Approved visual sources:

- [Native light appearance](/Users/maheshauti/Documents/Startups/pickSwitch/build/liquid-glass-qa/final-light.jpg).
- [Native dark appearance](/Users/maheshauti/Documents/Startups/pickSwitch/build/liquid-glass-qa/final-dark.jpg).
- [Native motion reference](/Users/maheshauti/Documents/Startups/pickSwitch/build/liquid-glass-qa/native-hub-motion.gif).
- Native motion implementation: Sources/VortexflowCore/Models/HubMotion.swift and HubChrome.swift.

Final comparisons, opened together for visual review:

- [Mac versus web, light](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/native-web-light.png).
- [Mac versus web, dark](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/native-web-dark.png).
- [Focused hub comparison](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/native-web-hub.png).

The native references are 851 × 768 normalized captures. Full-view comparisons crop the native widget at x90/y144, 640 × 600, and use the browser's 680 × 680 hero-widget capture. The hub comparison uses a 180 × 180 native crop and a 175 × 175 browser crop. Images are aspect-fitted into equal panels on 2800 × 1520 comparison sheets. There is no claim of identical device density, text rasterization or live window content.

Chrome desktop verification used 1920 × 993 CSS pixels at DPR 2; the capture provider normalizes ordinary screenshots to the content viewport. Mobile checks used 390 × 844 and 320 × 780. Temporary viewport overrides were reset. Initial in-app custom-viewport captures were clipped and were rejected for desktop comparison; after resetting and reloading, the normal in-app browser at approximately 1371 CSS pixels wide rendered both themes correctly.

## Required fidelity surfaces

- Fonts and typography: existing system fonts and website hierarchy retained. The center remains upright and does not scale with the animated rim. Mobile non-search captions were adjusted to avoid splitting a word such as “Release” across lines; search captions retain their larger, readable treatment.
- Spacing and layout: existing radial geometry and page sections retained. Outer-edge highlights now follow the correct arc direction. Mobile query bars clear both the appearance controls and the first action icon; the 320px check measured approximately 15px of icon clearance without overflowing the stage.
- Colors and tokens: translucent pastel surfaces in Light and low-luminance tinted surfaces in Dark, with soft colored edges and a fine white bevel. The web examples retain their existing app-color identities, so the example Chrome glow is green rather than the native fixture's amber. The optical hierarchy and motion match; this is not a claim that browser SVG/CSS reproduces the operating system's native refraction engine.
- Images and assets: existing real product icons, brand images and UI icons are reused. No flattened mock screenshot, new generated illustration, substitute brand logo or decorative asset was introduced. The widget's existing vector UI geometry remains interactive.
- Copy and content: homepage headings, feature copy, price, seven-day trial and availability notices are unchanged. Purchase/trial buttons remain disabled and clearly marked coming soon. Demo actions do not launch apps, send search queries or create purchases.

## Comparison history and fixes

1. P1: solid fills and a largely static center did not show the approved native treatment. Added translucent material styling, native-equivalent 3.8s breathing/7.6s traveling-light periods, bounded contour motion and both appearance variants.
2. P1: the first dark render exposed diagonal highlights across wedges. The existing outer-arc sweep direction was reversed; corrected it and recaptured. [Initial dark render](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/iteration-1-dark.jpg) versus final combined comparisons above.
3. P2: Light's inner-edge color was too strong relative to the native surface. Softened its colored rim and mixed the light ambience toward white, leaving Dark's edge depth intact.
4. P2: a small mobile hub broke “Release” mid-word, and the long query pill touched controls/covered the first action icon. Adjusted mobile caption sizing and separated query and radial content. The stage-level spacing rule was corrected after an initial container-query rule targeted the host rather than its descendant. Final mobile captures and geometry assertions pass.
5. P2 consistency: alternate-layout cards initially retained light colors when the surrounding demo was Dark. Added scoped dark surfaces and text colors without changing layout or behavior. [Verified Grid appearance](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/grid-dark.jpg).

## Functional verification

[Final browser checks](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/browser-checks-final.json): 19 checks passed, including:

- Search results and no-match web/AI actions.
- Enter-to-open behavior and in-demo feedback.
- Pinned scene, pin click and window-resize example.
- Circular glass and non-radial layout availability.
- Live contour changes with an unchanged caption rectangle.
- Pause, resume, reduced-motion static frames and offscreen animation shutdown.
- Global demo-appearance switching.
- Mobile overflow, control clearance and first-action-icon visibility.
- Clean captured browser consoles.

The source/browser comparison preserves the distinction between fixed UI geometry and moving optical paint. The motion clock is capped at 24 updates per second and stops when hidden, offscreen, disconnected, reduced or explicitly paused. This is not a sustained performance benchmark.

Additional evidence:

- [Mobile Windows](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/mobile-dark-final.jpg).
- [Final 320px search](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/mobile-search-320-final.jpg).
- [Final 390px search](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/mobile-search-final.jpg).
- [Pin and window-action close-ups](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/secondary-dark.jpg).
- [In-app Dark](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/iab-dark.jpg), [in-app Light](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/iab-light.jpg).

## Automated validation and limits

- Eight Node tests pass: motion timing, bounded contour, resting frames, pause/visibility policy, loop continuity, palette handling, all four widget integrations, local asset paths and structured metadata. [Test log](/Users/maheshauti/Documents/Startups/pickSwitch/build/site-glass-qa/unit-tests.log).
- JavaScript syntax and git diff whitespace checks pass.
- Both the Chrome and in-app browser captured no console warnings/errors.
- No waitlist submission, checkout, external search or public deployment was performed.
- System-level forced colors/reduced-transparency media modes were not manually changed. The fallback CSS is present; the interactive Reduced motion control was exercised.
- The historical blog screenshot is unchanged; the requested live product showcase is updated.
- Native app code, installed application, earlier uncommitted fixes and user-provided mock videos were preserved. The native suite was not rerun for this web-only turn.

## Handoff

The local preview is [http://127.0.0.1:4173/](http://127.0.0.1:4173/), with the updated in-app browser tab kept open. Implementation was prepared on codex/liquid-glass-widget. Publishing the site remains a separate, user-managed step. Screenshot and test-log links above refer to local, ignored QA artifacts rather than files bundled with the website.
