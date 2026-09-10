# Borders menu-bar and ring-light plan

Status: shipped

## Repository boundary

The menu-bar app should become its own small project rather than growing inside
this dotfiles repository. The standalone project can own the Swift source,
Xcode/SwiftPM build, app bundle metadata, tests, signing, and releases.

This repository should retain only the machine integration layer:

- Stow-managed default configuration;
- optional shell aliases or compatibility commands;
- a documented install/startup path for the standalone app;
- no app bundle, UI code, or build artifacts.

That keeps `n-dotfiles` declarative and makes the app independently usable on a
machine that does not use these dotfiles.

## What exists today

The original `Borders.app` is a small AppKit menu-bar application. It owns a
click-through overlay window with one `CAShapeLayer`, listens to WindowServer
notifications, and draws the focused-window ring without Accessibility or
camera permissions. The shell entrypoint remains useful for automation and
recovery:

```text
borders on|off|status|reconcile
```

The current `borders.conf` should remain the Stow-managed default configuration.
The menu-bar UI must not write through that symlink into the repository when a
slider is moved.

## Shipped menu-bar conversion

The standalone project contains the native `Borders.app`, following
the same pattern as `AudioPriorityBar`:

1. Set `LSUIElement=true` and use one `NSStatusItem` with a compact state
   icon and an accessible label.
2. The overlay/event code lives behind a `BorderEngine` object owned by the
   app. This avoids a second helper process and keeps the current one-process,
   low-memory design.
3. The CLI is a thin control client. It communicates with the app over a
   local Unix socket for immediate mode changes and status reporting.
4. The menu provides actions for `Focused window`, `Ring light`, `Off`, display
   selection, and `Open configuration`/`Reload`.
5. The app uses an app-owned preferences plist for live UI state. The Stow config stays
   the portable baseline; the menu bar stores machine-local overrides such as
   the last mode, selected display, width, colour, and brightness.
6. The app uses `SMAppService.mainApp` for login launch when the installed
   bundle owns startup. During migration, the existing LaunchAgent is
   disabled before the app starts, so two overlay engines cannot fight.

Adding an `NSStatusItem` directly to the current raw daemon is technically
possible and would be a smaller first patch, but it gives the menu action no
clean lifecycle: `KeepAlive` would immediately relaunch a daemon after Quit,
and the executable would still lack normal app-bundle metadata. A proper
`LSUIElement` app is the better long-term seam.

## Ring-light mode

Ring-light mode should be a separate renderer, not a special case in focused
window detection. It intentionally remains visible when a video-call app is
fullscreen, so it must bypass the focused-ring `isFullscreen` suppression.

### Geometry

- Create one transparent, click-through overlay per selected display.
- Draw a rounded rectangle inset by half the configured stroke width.
- Default to 24 points, with a slider covering roughly 8–40 points; 20–30
  points is the expected everyday range.
- Recompute display frames on display attach/detach and resolution changes.
- Respect the notch/safe-area geometry so the ring does not paint over the
  camera cutout or unexpectedly cover the menu bar.

macOS window geometry is expressed in points rather than physical pixels, so
the UI should label this as `Width` and describe it as display points if exact
physical-pixel sizing matters.

### Brightness and colour

The ring is a `CAShapeLayer`, so brightness and colour are cheap to change:

- brightness maps to the stroke alpha and, optionally, a small luminance
  adjustment so low values remain perceptually useful;
- a colour well or preset picker supplies the tint;
- a "colour filter" here means the light's tint (warm white, cool white,
  yellow, blue, etc.);
- there is no camera capture, camera permission, video processing, or camera
  integration in scope.

The overlay can optionally set its window sharing behavior to exclude it from
screen capture, so the light does not appear in screen shares or recordings.

### Display and call controls

The first version should use an explicit menu-bar toggle rather than trying to
detect an active call. The ring light is simply a display-edge light and does
not need to know which application is using a camera. A hotkey can be added
later if the manual toggle is not convenient.

Useful controls are:

```text
Mode: Off | Focused window | Ring light
Display: Main | Focused display | All displays
Width: 8–40 points
Brightness: 0–100%
Colour: colour well + warm/cool presets
```

## Footprint and risks

This remains a small applet if it keeps using vector layers: one status item,
one WindowServer event subscription, and one static overlay per display. The
ring-light mode should not need a timer or bitmap redraw; slider changes and
display notifications are enough. The main risks are lifecycle migration,
multi-display coordinate conversion, and accidentally allowing the overlay to
appear in screen capture.

## Implementation order

1. Create the standalone `borders` project and move the focused-ring source
   into it. **Done.**
2. Add a proper `Borders.app` target with the `AudioPriorityBar` status-item
   pattern and preserve the existing CLI commands. **Done.**
3. Add preferences/state separation so Stow owns defaults and the app owns
   runtime overrides. **Done.**
4. Add ring-light display geometry with fixed test fixtures for single,
   multi-display, and notched displays. **Done.**
5. Add the width, brightness, and colour controls. **Done.**
6. Add the small n-dotfiles integration layer once the app's install contract
   is stable. **Done.**
7. Replace the old LaunchAgent startup path only after the app and CLI agree
   on one running engine. **Done.**
