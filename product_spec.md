**Specification Document: Open-Source macOS App Switcher (Working Title: Orbit Switcher / Vortexflow)**

Inspired by **Dory – App Switcher** ($9.99 Mac App Store utility by Segev Sherry).  
Goal: Create a free, open-source alternative focused on **recent apps/windows**, **live previews**, and **pure mouse-driven switching** via Logitech MX Master 3 extra buttons.

---

### 1. Research Summary – Dory – App Switcher

**Core experience**  
- Zero-configuration app switcher + launcher.  
- Trigger: Middle mouse button (default), modifier key hold/tap/double-tap, global shortcut, trackpad gesture, or hyperkey.  
- Interaction: Trigger → type first letter / middle letters / acronym / similar name. Keep tapping the same letter to cycle matches.  
- Learns usage habits and prioritizes frequently used apps.  
- Can launch non-running apps.  
- UI modes: **List** (horizontal/pillar), **Palette** (swatch/card style), **Fan** (circular radial with unfurl animation). Multiple sizes (Small → Huge). Adjustable animation speed, arrow-key navigation.  
- Menu-bar utility, fully local, no data collection.  
- Price: $9.99 one-time. Requires recent macOS (15.2+ in current versions).  

**Limitations relevant to our goals**  
- App-level only (does **not** switch individual windows or browser tabs).  
- No window/application previews/thumbnails.  
- Not open source.  

**User’s desired deltas**  
- Strong emphasis on **recently opened / most-recently-used (MRU)** apps and windows.  
- **Live (or near-live) previews** of windows before switching.  
- Primary trigger & navigation via **MX Master 3 extra buttons** (Gesture button, side buttons, thumb wheel, etc.) so the user never needs to leave the mouse or press keyboard keys for the core workflow.  
- Fully open source.

---

### 2. Requirements Gathering

#### 2.1 User Stories (Priority)

**P0 – Must-have (MVP)**  
1. As a power user with an MX Master 3, I want to press one of the extra mouse buttons and immediately see my most recently used apps/windows so I can switch without touching the keyboard.  
2. As a user juggling many windows, I want to see a clear visual preview (thumbnail) of the window content **before** I switch so I know exactly what I’m activating.  
3. As a user, I want the list ordered by most-recently-activated (MRU) so the apps I just used are first.  
4. As a user, I want pure mouse navigation: hover or scroll to select, click/release to switch.  
5. As a privacy-conscious user, I want the app to be fully local, open source, and request only the necessary permissions (Accessibility + Screen Recording).

**P1 – Should-have**  
6. Support switching to a specific window of a multi-window app (not just the app).  
7. Optional type-to-filter (fuzzy search) as a secondary method.  
8. Ability to exclude apps, pin favorites, and control history length.  
9. Multiple UI layouts (radial/fan, horizontal strip, grid).  
10. Hold-to-show / release-to-switch and press-to-toggle modes.  

**P2 – Nice-to-have**  
11. Launch non-running apps.  
12. Multi-monitor awareness and placement near cursor.  
13. Custom animation speed and glassmorphism themes.  
14. Integration helpers for Logi Options+ / BetterMouse.

#### 2.2 Functional Requirements

**Core**  
- Maintain an ordered list of running applications and their windows sorted primarily by last activation time (MRU). Optional secondary weighting by frequency.  
- Display live or snapshot window thumbnails (preferred: ScreenCaptureKit).  
- Show for each entry: app icon, app name, window title, and thumbnail.  
- Activate (bring to front + unminimize if needed) the selected app/window.  
- Support both “App mode” (one entry per app, preview of its frontmost/recent window) and “Window mode” (every window is a separate selectable card).  

**Triggering & Navigation (Mouse-first)**  
- Primary triggers: Configurable mouse buttons (middle, side, Gesture button, etc.).  
- Secondary: Global hotkey (so users can map any MX Master 3 button via Logi Options+).  
- Modes:  
  - Hold trigger → show overlay → move mouse / scroll → release to switch.  
  - Press trigger → show overlay → click or scroll + click to switch.  
- While open: mouse wheel / thumb wheel cycles selection; hover highlights and optionally enlarges the preview.  

**Customization**  
- Choose default layout, size, opacity, animation speed.  
- Include/exclude list, pin favorites, history depth.  
- Light/Dark/System appearance.  

**Permissions & Setup**  
- Guide the user through Accessibility and Screen Recording permissions on first launch.  
- Optional Input Monitoring if direct high-level mouse button listening is used.

#### 2.3 Non-Functional Requirements

- Native macOS feel, lightweight (< 50–80 MB RAM idle, low CPU when not showing).  
- Low latency: overlay appears in < 100–150 ms.  
- Privacy-first: no network, no telemetry, no cloud.  
- Compatible with macOS 14+ (ScreenCaptureKit) or 15+ preferred. Apple Silicon + Intel.  
- Open source (recommended: MIT for maximum adoption, or GPL-3.0).  
- Accessible (VoiceOver support as stretch goal).

---

### 3. Look and Feel / UI/UX Design

**Design principles**  
- Mouse-centric first, keyboard optional.  
- Clean, modern, native macOS aesthetic (vibrancy, blur, SF Symbols, glassmorphism).  
- Inspired by Dory’s delightful Fan/List/Palette animations + the clarity of Windows Alt-Tab / macOS Mission Control / AltTab.app previews.  
- Never feel cluttered: prioritize recent items; collapse or dim older ones.

**Proposed UI Modes**

1. **Radial / Fan Mode** (closest to Dory’s signature look)  
   - Apps/windows arranged in an arc or full circle around the cursor or screen center.  
   - Large live thumbnail pops out or enlarges on hover.  
   - Smooth unfurl animation (configurable speed: Instant → Normal).  
   - Mouse movement selects the sector; release or click activates.

2. **Horizontal Strip / Carousel**  
   - Row of cards (thumbnail + icon + title) ordered by MRU.  
   - Scroll with mouse wheel or drag.  
   - Selected item scales up and shows a larger preview above/below.

3. **Grid / Mission-Control-lite**  
   - Adaptive grid of window thumbnails (2×2 → 4×4 depending on count).  
   - Hover or arrow keys (optional) to select.  
   - Best when many windows are open.

4. **List + Preview Pane** (optional power-user mode)  
   - Compact vertical list of recent apps on the left.  
   - Large live preview of the highlighted window on the right.

**Visual details**  
- Translucent dark or light panel with subtle shadow and rounded corners.  
- Highlight: soft glow + scale (1.05–1.1×) + border.  
- Window title and app name always readable.  
- Optional badge showing number of windows for multi-window apps.  
- Placement: centered, or near mouse cursor, or on the active display only.  
- Exit: click outside, Escape, or release of hold-trigger without selection.

**Animation & Polish**  
- Smooth fade + scale in/out.  
- Optional haptic feedback on selection (if supported).  
- Respect Reduce Motion.  
- Snappy default; user can slow it down for the “delightful” Dory-like feel.

---

### 4. High-Level Technical Considerations (for later phases)

- **Language/UI**: Swift + SwiftUI (overlay) + AppKit where needed.  
- **App/Window enumeration**: NSWorkspace + Accessibility (AXUIElement) or CGWindowList.  
- **Previews**: ScreenCaptureKit (preferred) for high-quality, efficient thumbnails. Capture on-demand when the switcher opens; optional low-FPS live stream only for the hovered item.  
- **Mouse events**: CGEventTap (with appropriate permissions) or global hotkey registration.  
- **MX Master 3**: Document recommended Logi Options+ mappings (Gesture button → rare key combo or “Do Nothing” + event-tap listening). Support companion tools (BetterMouse, myMouseMagic, etc.).  
- **Activation**: NSRunningApplication.activate or Accessibility raise actions.

**Existing open-source references to study**  
- alt-tab-macos (excellent window previews + configurability).  
- DockDoor (Dock hover previews).  
- Overview and similar Swift-based preview tools.

---

### 5. Open-Source Plan (initial)

- License: MIT (recommended) or GPL-3.0.  
- Repository: GitHub (or equivalent).  
- README with clear permission setup, MX Master 3 configuration guide, and screenshots/GIFs.  
- Roadmap: MVP (MRU + previews + mouse trigger) → multi-window mode → advanced customization → packaging (Homebrew + direct download).

---

### Next Steps

This document focuses on **requirement gathering** and **look & feel** as requested.  

Would you like me to:  
1. Expand any section into more detail (user stories, wireframe descriptions, permission flows)?  
2. Propose a concrete project name and logo concept?  
3. Draft the initial technical architecture or MVP task breakdown?  
4. Generate visual mockup descriptions or search for reference screenshots of similar UIs?

Just say the word and the team will refine it further.