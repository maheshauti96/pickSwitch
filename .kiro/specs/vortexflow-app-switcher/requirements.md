# Requirements Document

## Introduction

Vortexflow is a free, open-source, menu-bar-only macOS utility that lets a user switch between open windows using only the mouse. Pressing a configured extra mouse button opens a horizontal strip of cards near the cursor. Each card represents one individual window and shows a thumbnail of that window's content, the owning application's icon and name, and the window title. Cards are ordered most-recently-used first. Rotating the scroll wheel or thumb wheel moves the selection.

What a release of the button does depends on the Activation_Mode: holding and releasing activates the selected window, while a brief tap leaves the Strip on screen so the user can read it and then click. This was not in the original draft of this document and was added after use: hold-and-release is the faster gesture once the user knows their target, but it cannot serve the equally common case of opening the switcher in order to *look* at what is open.

Version 1 is a window-level switcher from day one: every window is its own card with its own thumbnail and its own most-recently-used timestamp. The horizontal strip is the only layout. Thumbnails come from ScreenCaptureKit. Triggering uses a CGEventTap on raw mouse buttons, with a global hotkey as a secondary fallback. The application performs no network activity and collects no telemetry.

This document specifies the version 1 minimum viable product only. Section "Out of Scope for Version 1" records the deferred capabilities so that no requirement above is read as covering them.

## Glossary

- **Vortexflow_App**: The complete macOS application bundle, including all components below.
- **Window_Registry**: The component that enumerates windows of running applications and produces Window_Entries.
- **Window_Entry**: The in-memory record of one individual open window, holding the owning application name, application icon, window title, window identifier, on-screen bounds, and minimized state.
- **MRU_Tracker**: The component that records and orders per-window last-activation timestamps.
- **MRU_Order**: The ordering of Window_Entries by descending last-activation timestamp.
- **Overlay**: The on-screen switcher surface: a floating, translucent panel containing the horizontal strip of Window_Cards.
- **Strip**: The single horizontal, scrollable row of Window_Cards inside the Overlay. The Strip is the only layout in version 1.
- **Window_Card**: The visual representation of one Window_Entry inside the Strip.
- **Selected_Card**: The one Window_Card that a release of the Trigger_Button or a press of the Return key will activate.
- **Trigger_Monitor**: The component that installs and maintains the CGEventTap and the global hotkey registration.
- **Trigger_Button**: The single mouse button configured to open the Overlay. Any button number from 2 through 31 inclusive. Buttons 0 and 1 are the primary and secondary buttons and are excluded, because consuming either would break ordinary clicking system-wide. The original draft permitted only middle, button 4 and button 5; that proved too narrow, since the extra buttons on real mice report numbers outside that set.
- **Button_Capture**: A Settings mode in which the next Other_Mouse_Event is reported to the user and assigned as the Trigger_Button, instead of opening the Overlay.
- **Activation_Mode**: How a press of the Trigger_Button behaves. One of Automatic, Hold, or Toggle.
- **Tap_Threshold**: The press duration below which a press counts as a tap rather than a hold in Automatic mode. 250 ms.
- **Other_Mouse_Event**: A macOS event of type `otherMouseDown` or `otherMouseUp`, that is, a press or release of a mouse button other than the primary or secondary button.
- **Global_Hotkey**: The keyboard-based trigger that opens the Overlay, chosen from a fixed set of preset combinations. Control+Option+Space is the default. The original draft fixed it at Control+Option+Space with no way to change it; that proved untenable, because macOS reports successful registration even when another process already owns a combination and silently keeps the keystroke, leaving the user with an inert shortcut and no recourse.
- **Thumbnail_Service**: The component that captures window images through ScreenCaptureKit and supplies them to Window_Cards.
- **Live_Stream**: A ScreenCaptureKit capture stream that delivers repeating frames for a single Window_Card.
- **Activation_Service**: The component that raises, unminimizes, and focuses a target window.
- **Permissions_Manager**: The component that reads the authorization status of Input Monitoring, Accessibility, and Screen Recording and drives the first-launch setup flow.
- **Required_Authorizations**: The set of three macOS authorizations Input Monitoring, Accessibility, and Screen Recording.
- **Onboarding_Window**: The first-launch window that reports the status of each of the Required_Authorizations and links to the matching System Settings pane.
- **Menu_Bar_Controller**: The component that owns the menu bar status item and its menu.
- **Settings_Window**: The version 1 settings surface.
- **Settings_Store**: The component that persists user preferences across launches.
- **History_Depth**: The user-configurable maximum number of Window_Cards the Overlay displays.
- **Active_Display**: The display whose bounds contain the mouse cursor at the moment the Overlay is presented.
- **Reference_Machine**: An Apple Silicon Mac running macOS 15.0 or later with 12 or fewer Window_Entries present, used as the measurement condition for timing, memory, and CPU criteria.

## Requirements

### Requirement 1: Per-Window Enumeration

**User Story:** As a user juggling many windows across a few applications, I want every open window to appear as its own entry, so that I can jump straight to the specific window I need instead of only to an application.

#### Acceptance Criteria

1. THE Window_Registry SHALL represent each open standard window of each running application as one distinct Window_Entry.
2. WHEN the Trigger_Monitor reports a trigger press, THE Window_Registry SHALL produce the current set of Window_Entries within 50 ms on the Reference_Machine.
3. THE Window_Registry SHALL record for each Window_Entry the owning application name, the owning application icon, the window title, the window identifier, the on-screen bounds, and the minimized state.
4. IF a window reports a minimized state, THEN THE Window_Registry SHALL include the window as a Window_Entry and mark the minimized state as true.
5. THE Window_Registry SHALL restrict Window_Entries to windows that the Accessibility API reports with a standard window role, so that menu bar items, the desktop, notification banners, and system panels stay out of the Window_Entry set.
6. THE Window_Registry SHALL restrict Window_Entries to windows owned by applications other than the Vortexflow_App.
7. WHEN a window is opened, closed, or retitled while the Overlay is hidden, THE Window_Registry SHALL reflect the change in the Window_Entry set produced for the next Overlay presentation.
8. IF the Window_Registry produces zero Window_Entries, THEN THE Overlay SHALL display a single message stating that no switchable windows are open.

### Requirement 2: Per-Window Most-Recently-Used Ordering

**User Story:** As a user who moves between the same two or three windows all day, I want the windows I used most recently to appear first, so that the window I want is nearly always one of the first cards.

#### Acceptance Criteria

1. THE MRU_Tracker SHALL store one last-activation timestamp per Window_Entry.
2. WHEN a window becomes the focused window of the frontmost application, THE MRU_Tracker SHALL set the last-activation timestamp of the matching Window_Entry to the current system time.
3. WHEN the Overlay is presented, THE Strip SHALL arrange Window_Cards in MRU_Order from left to right.
4. WHEN the Overlay is presented, THE Strip SHALL place the Window_Card of the currently focused window in the leftmost position.
5. WHEN the Overlay is presented, THE Overlay SHALL set the Selected_Card to the second Window_Card in MRU_Order, so that a press and release of the Trigger_Button without pointer movement returns the user to the previously used window.
6. WHERE a Window_Entry carries no last-activation timestamp from the current Vortexflow_App session, THE MRU_Tracker SHALL assign an initial timestamp derived from the window's front-to-back position in the system window list, with frontmost windows receiving the most recent timestamps.
7. WHEN the number of Window_Entries exceeds the configured History_Depth, THE Strip SHALL display the History_Depth most recently activated Window_Entries.
8. WHEN a window closes, THE MRU_Tracker SHALL discard the last-activation timestamp of the matching Window_Entry.

### Requirement 3: Horizontal Strip Presentation

**User Story:** As a user glancing at the switcher for a fraction of a second, I want a single readable row of window previews, so that I can identify the target window by its content rather than by its name alone.

#### Acceptance Criteria

1. THE Overlay SHALL present Window_Cards as a single horizontal Strip.
2. THE Window_Card SHALL display the window thumbnail, the owning application icon, the owning application name, and the window title.
3. WHEN a Window_Card becomes the Selected_Card, THE Strip SHALL render that Window_Card at a scale between 1.05 and 1.10 times the size of an unselected Window_Card.
4. WHEN a Window_Card becomes the Selected_Card, THE Thumbnail_Service SHALL supply a preview image for that Window_Card at no less than twice the linear pixel dimensions of an unselected Window_Card thumbnail.
5. WHEN the pointer enters the bounds of a Window_Card, THE Strip SHALL render that Window_Card with a highlight consisting of a border and a raised background brightness.
6. WHERE an application owns two or more of the displayed Window_Entries, THE Strip SHALL display on each of that application's Window_Cards a badge showing the count of that application's displayed Window_Entries.
7. THE Window_Card SHALL display the window title on one line and truncate the window title with a trailing ellipsis when the window title exceeds the Window_Card width.
8. WHEN the combined width of the Window_Cards exceeds the width of the Overlay, THE Strip SHALL scroll horizontally so that the Selected_Card stays fully within the Overlay bounds.
9. THE Overlay SHALL render a translucent background panel with rounded corners and a drop shadow.
10. THE Overlay SHALL follow the system appearance setting for light and dark rendering.
11. THE Overlay SHALL render the application name text and the window title text at a contrast ratio of at least 4.5 to 1 against the Window_Card background.

### Requirement 4: Mouse-Only Selection

**User Story:** As a power user with a hand on the mouse, I want to move the selection with the wheel or by pointing, so that I never reach for the keyboard during a switch.

#### Acceptance Criteria

1. WHILE the Overlay is visible, WHEN a scroll wheel event is received, THE Strip SHALL move the Selected_Card by one Window_Card per discrete wheel step.
2. THE Strip SHALL coalesce continuous scroll deltas so that one physical wheel notch moves the Selected_Card by exactly one Window_Card.
3. WHILE the Overlay is visible, WHEN a scroll step in the downward or rightward direction is received, THE Strip SHALL move the Selected_Card one position to the right.
4. WHILE the Overlay is visible, WHEN a scroll step in the upward or leftward direction is received, THE Strip SHALL move the Selected_Card one position to the left.
5. WHILE the Selected_Card is the rightmost Window_Card, WHEN a scroll step in the downward or rightward direction is received, THE Strip SHALL set the Selected_Card to the leftmost Window_Card.
6. WHILE the Selected_Card is the leftmost Window_Card, WHEN a scroll step in the upward or leftward direction is received, THE Strip SHALL set the Selected_Card to the rightmost Window_Card.
7. WHILE the Overlay is visible, WHEN the pointer moves onto a Window_Card, THE Overlay SHALL set the Selected_Card to the Window_Card under the pointer.
8. WHEN the Selected_Card changes, THE Strip SHALL complete the updated selection rendering within 50 ms on the Reference_Machine.

### Requirement 5: Mouse Button Trigger

**User Story:** As an MX Master owner, I want to press one of my extra mouse buttons to reveal the switcher, and I want a brief tap to leave it on screen so I can read it, so that one button covers both switching fast and browsing what is open.

#### Acceptance Criteria

1. WHEN the Vortexflow_App launches, THE Trigger_Monitor SHALL install a CGEventTap that observes Other_Mouse_Events system-wide.
2. WHILE the Overlay is hidden, THE Trigger_Monitor SHALL subscribe the CGEventTap to Other_Mouse_Event types only, so that primary mouse button, secondary mouse button, scroll wheel, and keyboard events bypass the CGEventTap.
3. WHEN an Other_Mouse_Event whose button number differs from the configured Trigger_Button is observed, THE Trigger_Monitor SHALL forward the event unmodified to the destination application.
4. WHEN an Other_Mouse_Event whose button number matches the configured Trigger_Button is observed, THE Trigger_Monitor SHALL consume the event and withhold the event from the destination application.
5. WHEN a press of the configured Trigger_Button is observed, THE Overlay SHALL become visible.
6. WHILE the Overlay is visible, THE Trigger_Monitor SHALL extend the CGEventTap subscription to scroll wheel events and key press events.
7. WHILE the Overlay is visible, WHEN a scroll wheel event or a key press event is observed, THE Trigger_Monitor SHALL deliver the event to the Overlay and withhold the event from the destination application.
8. WHEN the Overlay dismisses, THE Trigger_Monitor SHALL return the CGEventTap subscription to Other_Mouse_Event types only.
9. WHILE the configured Trigger_Button remains held, THE Overlay SHALL remain visible.
10. WHILE the Activation_Mode is Hold AND a Selected_Card exists, WHEN the configured Trigger_Button is released, THE Activation_Service SHALL activate the window of the Selected_Card.
15. WHILE the Activation_Mode is Automatic, WHEN the configured Trigger_Button is released after being held for at least the Tap_Threshold, THE Activation_Service SHALL activate the window of the Selected_Card.
16. WHILE the Activation_Mode is Automatic, WHEN the configured Trigger_Button is released after being held for less than the Tap_Threshold, THE Overlay SHALL remain visible and SHALL NOT activate any window.
17. WHILE the Activation_Mode is Toggle, WHEN the configured Trigger_Button is released, THE Overlay SHALL remain visible and SHALL NOT activate any window.
18. WHILE the Overlay is visible and is not tracking a held button, WHEN the configured Trigger_Button is pressed, THE Activation_Service SHALL activate the window of the Selected_Card.
19. WHILE the Overlay is visible and is not tracking a held button, THE Overlay SHALL display a hint stating that clicking a Window_Card or pressing the Trigger_Button again will switch, and that Escape cancels.
20. WHILE Button_Capture is active, WHEN any Other_Mouse_Event is observed, THE Trigger_Monitor SHALL consume the event, SHALL NOT present the Overlay, and SHALL report the observed button number to the Settings_Window.
11. THE Trigger_Monitor SHALL complete each CGEventTap callback within 5 ms on the Reference_Machine, deferring enumeration, capture, and rendering work to other dispatch queues.
12. IF macOS disables the CGEventTap for a timeout or for user input, THEN THE Trigger_Monitor SHALL re-enable the same CGEventTap within 1 second of receiving the disabled notification.
13. IF macOS disables the CGEventTap three times within 60 seconds, THEN THE Menu_Bar_Controller SHALL display a warning indicator on the status item reporting repeated trigger interruption.
14. IF creation of the CGEventTap fails, THEN THE Trigger_Monitor SHALL report the failure to the Permissions_Manager and continue operating with the Global_Hotkey as the only trigger.

### Requirement 6: Global Hotkey Fallback Trigger

**User Story:** As a user whose mouse buttons are claimed by another tool, I want a keyboard shortcut that opens the same switcher, so that Vortexflow stays usable while I sort out my mouse configuration.

#### Acceptance Criteria

1. WHEN the Vortexflow_App launches, THE Trigger_Monitor SHALL register the Global_Hotkey as a secondary trigger.
2. WHEN the Global_Hotkey is pressed, THE Overlay SHALL become visible and remain visible until an activation or a dismissal occurs.
3. WHILE the Overlay is visible, WHEN the primary mouse button is clicked on a Window_Card, THE Activation_Service SHALL activate the window of that Window_Card.
4. WHILE the Overlay is visible, WHEN the Return key is pressed, THE Activation_Service SHALL activate the window of the Selected_Card.
5. IF registration of the Global_Hotkey fails, THEN THE Menu_Bar_Controller SHALL display a warning indicator on the status item reporting the unavailable shortcut.
6. THE Trigger_Monitor SHALL observe both press and release of the Global_Hotkey, and SHALL apply the same Activation_Mode rules to a Global_Hotkey release as to a Trigger_Button release.
7. THE Settings_Window SHALL offer the Global_Hotkey as a choice from the preset set, and SHALL include at least one preset that uses no modifier keys.
8. THE Settings_Window SHALL report whether the configured Global_Hotkey has been observed to fire at least once since registration, because successful registration does not establish that the combination is reaching the Vortexflow_App.

Criteria 6 and 7 exist for a hardware reason worth recording. Logi Options+ intercepts the extra buttons on Logitech mice inside its own driver, and a button assigned to "Do Nothing" is discarded rather than passed through, so it never reaches the CGEventTap and cannot be captured. The only route to using such a button is to assign it to a keyboard shortcut in Options+. Handling Global_Hotkey release, and offering a modifier-free preset such as F13, makes a button remapped that way behave identically to a real Trigger_Button.

### Requirement 7: Window Activation

**User Story:** As a user selecting a window, I want that exact window brought to the front and ready for input, so that the switch needs no follow-up clicks.

#### Acceptance Criteria

1. WHEN activation of a Window_Entry is requested, THE Overlay SHALL become hidden within 100 ms of the request.
2. WHEN activation of a Window_Entry is requested, THE Activation_Service SHALL raise the target window above the other windows of the owning application using the Accessibility raise action.
3. WHEN activation of a Window_Entry is requested, THE Activation_Service SHALL activate the owning application so that the target window receives keyboard focus.
4. IF the target Window_Entry carries a minimized state of true, THEN THE Activation_Service SHALL unminimize the target window before raising the target window.
5. IF the owning application is hidden, THEN THE Activation_Service SHALL unhide the owning application before raising the target window.
6. THE Activation_Service SHALL complete activation within 200 ms of the activation request on the Reference_Machine.
7. IF the target window no longer exists at the moment of activation, THEN THE Activation_Service SHALL leave the current frontmost window focused.
8. IF the target window no longer exists at the moment of activation, THEN THE Window_Registry SHALL discard the stale Window_Entry.

### Requirement 8: Dismissal Without Switching

**User Story:** As a user who opened the switcher and changed my mind, I want an obvious way out that leaves my current window untouched, so that an accidental trigger costs me nothing.

#### Acceptance Criteria

1. WHILE the Overlay is visible, WHEN the Escape key is pressed, THE Overlay SHALL dismiss and leave the currently frontmost window focused.
2. WHILE the Overlay is visible, WHEN the primary mouse button is clicked outside the Overlay bounds, THE Overlay SHALL dismiss and leave the currently frontmost window focused.
3. WHILE the Overlay is visible and no Selected_Card exists, WHEN the configured Trigger_Button is released, THE Overlay SHALL dismiss and leave the currently frontmost window focused.
4. WHILE the Overlay is visible, WHEN the set of connected displays changes, THE Overlay SHALL dismiss and leave the currently frontmost window focused.
5. WHEN the Overlay dismisses, THE Thumbnail_Service SHALL stop every Live_Stream within 200 ms.
6. WHEN the Overlay dismisses, THE Thumbnail_Service SHALL release every captured window image from memory.

### Requirement 9: Window Thumbnails

**User Story:** As a user with four similar documents open, I want to see what is inside each window before switching, so that I pick the right one on the first try.

#### Acceptance Criteria

1. WHEN a trigger press is observed, THE Thumbnail_Service SHALL request one still image for each displayed Window_Entry through ScreenCaptureKit.
2. THE Thumbnail_Service SHALL deliver still images asynchronously so that Overlay presentation proceeds before image delivery completes.
3. THE Overlay SHALL display the owning application icon as the Window_Card image until the captured still image for that Window_Card arrives.
4. THE Thumbnail_Service SHALL deliver still images for the first eight Window_Cards in MRU_Order within 150 ms of the capture request on the Reference_Machine.
5. THE Thumbnail_Service SHALL scale every delivered image to preserve the source window's aspect ratio.
6. WHERE a Window_Card is the Selected_Card, THE Thumbnail_Service SHALL supply a Live_Stream for that Window_Card at no more than 10 frames per second.
7. THE Thumbnail_Service SHALL hold at most one active Live_Stream at any moment.
8. WHEN the Selected_Card changes, THE Thumbnail_Service SHALL stop the Live_Stream of the previous Selected_Card within 200 ms.
9. IF ScreenCaptureKit returns no image for a Window_Entry, THEN THE Overlay SHALL display the owning application icon as that Window_Card's image.
10. THE Thumbnail_Service SHALL retain captured images in volatile memory for the duration of one Overlay presentation.

### Requirement 10: Permissions and First-Launch Setup

**User Story:** As a first-time user, I want Vortexflow to tell me exactly which permissions it needs and why, so that I can get it working without hunting through System Settings.

#### Acceptance Criteria

1. WHEN the Vortexflow_App launches, THE Permissions_Manager SHALL determine the current authorization status of each of the Required_Authorizations.
2. IF one or more of the Required_Authorizations is ungranted at launch, THEN THE Permissions_Manager SHALL present the Onboarding_Window.
3. THE Onboarding_Window SHALL display for each of the Required_Authorizations the purpose of that authorization and the current status of that authorization.
4. THE Onboarding_Window SHALL provide for each of the Required_Authorizations a control that opens the matching System Settings privacy pane.
5. WHILE the Onboarding_Window is visible, WHEN an authorization status changes, THE Onboarding_Window SHALL display the new status within 2 seconds.
6. WHILE all of the Required_Authorizations are granted, THE Permissions_Manager SHALL start the Vortexflow_App without presenting the Onboarding_Window.
7. THE Onboarding_Window SHALL display instructions for assigning the Logitech MX Master 3 Gesture button to "Do Nothing" in Logi Options+ so that the Gesture button reaches the CGEventTap as a raw mouse button.
8. WHILE Screen Recording authorization is ungranted, THE Overlay SHALL display owning application icons as Window_Card images and SHALL continue to support selection and activation.
9. WHILE Input Monitoring authorization is ungranted, THE Trigger_Monitor SHALL operate with the Global_Hotkey as the only trigger.
10. WHILE Accessibility authorization is ungranted, THE Activation_Service SHALL activate the owning application of the Selected_Card in place of the individual target window.
11. WHILE one or more of the Required_Authorizations is ungranted, THE Menu_Bar_Controller SHALL display a warning indicator on the status item.

### Requirement 11: Menu Bar Utility Behavior

**User Story:** As a user of a background utility, I want Vortexflow to live in the menu bar and stay out of my Dock and app switcher, so that it behaves like the small tool it is.

#### Acceptance Criteria

1. THE Vortexflow_App SHALL declare itself a user interface element agent so that macOS omits the Vortexflow_App from the Dock and from the system application switcher.
2. WHEN the Vortexflow_App launches, THE Menu_Bar_Controller SHALL display a status item in the system menu bar.
3. WHEN the user activates the status item, THE Menu_Bar_Controller SHALL display a menu containing a permissions status summary, a control that opens the Settings_Window, the application version, and a quit control.
4. WHEN the user selects the quit control, THE Trigger_Monitor SHALL remove the CGEventTap and unregister the Global_Hotkey.
5. WHEN the user selects the quit control, THE Vortexflow_App SHALL terminate within 1 second.

### Requirement 12: Version 1 Settings

**User Story:** As a user with a specific mouse and specific habits, I want to choose which button triggers the switcher, how it behaves when I press it, and how many windows it lists, so that Vortexflow fits my hardware rather than the other way round.

#### Acceptance Criteria

1. THE Settings_Window SHALL present a Trigger_Button selector, a Button_Capture control, an Activation_Mode selector, a Global_Hotkey selector, a permissions status section, and a History_Depth control.
2. THE Trigger_Button selector SHALL offer middle mouse button, thumb back, and thumb forward as presets, and SHALL additionally offer the currently configured button when it is not one of those presets.
2a. WHEN the user activates the Button_Capture control, THE Settings_Window SHALL assign the next observed mouse button as the Trigger_Button, and SHALL report when the observed button cannot be used.
2b. IF the Trigger_Button is one that applications commonly rely on, THEN THE Settings_Window SHALL state what will stop working as a result.
2c. THE Settings_Window SHALL explain that a Logitech thumb or Gesture button cannot be captured, and SHALL direct the user to assign it to a keyboard shortcut in Logi Options+ instead.
3. WHEN the user chooses a different Trigger_Button value, THE Trigger_Monitor SHALL apply the chosen value to subsequent Other_Mouse_Events without an application restart.
4. THE History_Depth control SHALL accept integer values from 5 through 25 inclusive.
5. WHEN the user changes the History_Depth value, THE Strip SHALL apply the new value at the next Overlay presentation.
6. THE permissions status section SHALL display the current status of each of the Required_Authorizations and a control that opens the matching System Settings privacy pane.
7. THE Settings_Store SHALL persist the Trigger_Button value, the History_Depth value, the Activation_Mode value, and the Global_Hotkey value across application launches, and SHALL persist nothing else.
8. WHEN the Vortexflow_App launches with no persisted settings, THE Settings_Store SHALL apply a Trigger_Button value of middle mouse button, a History_Depth value of 10, an Activation_Mode of Automatic, and the default Global_Hotkey.
9. IF a persisted value is not recognised, THEN THE Settings_Store SHALL apply the corresponding default rather than failing.
10. WHEN the user changes the Activation_Mode or the Global_Hotkey, THE Vortexflow_App SHALL apply the change without an application restart.

### Requirement 13: Overlay Placement

**User Story:** As a user on a multi-monitor desk, I want the switcher to appear where my cursor already is, so that my hand travels the shortest possible distance.

#### Acceptance Criteria

1. WHEN the Overlay is presented, THE Overlay SHALL appear on the Active_Display.
2. WHEN the Overlay is presented, THE Overlay SHALL center the Overlay frame on the current cursor position.
3. IF the centered Overlay frame extends beyond the visible frame of the Active_Display, THEN THE Overlay SHALL shift the Overlay frame so that the whole Overlay frame lies within the visible frame of the Active_Display.
4. THE Overlay SHALL present as a non-activating floating panel so that the frontmost application retains keyboard focus while the Overlay is visible.
5. THE Overlay SHALL render above the normal application windows of the Active_Display.
6. WHERE the Active_Display presents a full-screen space, THE Overlay SHALL render inside that space.

### Requirement 14: Performance and Resource Use

**User Story:** As a user who triggers the switcher dozens of times an hour, I want it to appear instantly and cost nothing while idle, so that it feels like part of the system rather than an extra program.

#### Acceptance Criteria

1. WHEN a press of the configured Trigger_Button is observed, THE Overlay SHALL become visible within 150 ms on the Reference_Machine.
2. WHEN the Overlay is presented, THE Overlay SHALL complete the appearance transition within 200 ms.
3. WHILE the Overlay is hidden, THE Vortexflow_App SHALL consume less than 1 percent of one CPU core measured as a 60-second average on the Reference_Machine.
4. WHILE the Overlay is hidden, THE Vortexflow_App SHALL occupy less than 80 MB of resident memory on the Reference_Machine.
5. WHILE the Overlay is hidden, THE Thumbnail_Service SHALL hold zero active Live_Streams.
6. WHILE the Overlay is visible, THE Strip SHALL render selection changes at no fewer than 60 frames per second on a 60 Hz display.

### Requirement 15: Motion and Legibility Preferences

**User Story:** As a user who disables interface animation, I want the switcher to honor that choice, so that a tool I use constantly does not make me uncomfortable.

#### Acceptance Criteria

1. WHILE the system Reduce Motion setting is enabled, THE Overlay SHALL present and dismiss using an immediate appearance change in place of the fade and scale transition.
2. WHILE the system Reduce Motion setting is enabled, THE Strip SHALL render the Selected_Card at a scale of 1.0 and SHALL indicate the selection using border and background brightness changes.
3. WHILE the system Reduce Motion setting is enabled, THE Strip SHALL move the Strip scroll position to the Selected_Card without a scrolling animation.
4. WHEN the system Reduce Motion setting changes while the Overlay is hidden, THE Overlay SHALL apply the new setting at the next Overlay presentation.

### Requirement 16: Privacy and Licensing

**User Story:** As a privacy-conscious user installing a tool that can see all my window contents, I want provable local-only behavior and open source code, so that I can trust what I am running.

#### Acceptance Criteria

1. THE Vortexflow_App SHALL perform every function using local system APIs, with zero outbound network connections.
2. THE Vortexflow_App SHALL ship with zero analytics, telemetry, or crash-reporting components.
3. THE Settings_Store SHALL persist only the Trigger_Button value and the History_Depth value.
4. THE Window_Registry SHALL hold window titles in volatile memory for the lifetime of the process.
5. THE Vortexflow_App SHALL request only the Required_Authorizations.
6. THE Vortexflow_App source repository SHALL include the MIT license text in a LICENSE file at the repository root.

### Requirement 17: Platform and Implementation Constraints

**User Story:** As the maintainer of a small open-source utility, I want a single modern platform target, so that the codebase carries no compatibility branching.

#### Acceptance Criteria

1. THE Vortexflow_App SHALL declare a minimum deployment target of macOS 15.0.
2. THE Vortexflow_App SHALL build as a universal binary containing arm64 and x86_64 slices.
3. THE Vortexflow_App SHALL call macOS 15.0 APIs directly, with zero availability branching for macOS versions earlier than 15.0.
4. THE Vortexflow_App SHALL be implemented in Swift, using SwiftUI for the Overlay presentation and AppKit for window management and event handling.
5. THE Window_Registry SHALL enumerate windows using the Accessibility API and the Core Graphics window list.
6. THE Thumbnail_Service SHALL capture window images using ScreenCaptureKit.

## Out of Scope for Version 1

The following capabilities are deliberately excluded from this document. No requirement above covers them, and no design or task work should assume them.

- Radial or fan layout, grid layout, and list-plus-preview layout. The Strip is the only version 1 layout.
- Type-to-filter and fuzzy search.
- Launching applications that are not running.
- Application-level switching mode as a user-selectable alternative to per-window switching.
- Customization of Overlay size, opacity, animation speed, and appearance override.
- An arbitrary user-recorded Global_Hotkey. Selection from a preset set is in scope, per Requirement 6; a full shortcut recorder is not.
- Application exclude lists and pinned favorites.
- Browser tab switching.
- Persisting MRU history across application launches.
- Haptic feedback on selection.
- VoiceOver and full assistive-technology support, which remain a stretch goal for a later version.
- Homebrew and notarized-installer packaging.
