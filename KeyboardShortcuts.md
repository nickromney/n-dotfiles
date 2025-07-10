# Keyboard Shortcuts Configuration

This document outlines the keyboard shortcuts and modifications used in this dotfiles setup.

## Hyperkey Configuration

### Overview

The **Hyperkey** is a virtual modifier that combines all four modifiers: `⌘ + ⌥ + ⌃ + ⇧` (Command + Option + Control + Shift). This creates a dedicated modifier that's unlikely to conflict with any existing shortcuts.

### Implementation

Due to issues with Karabiner-Elements on work machines wanting to access a protected setting that is governed by a profile, I use the following tools - Keyboard Scroller is free, but I have paid for the other two which I find very useful for keyboard-centric searching

- **[Superkey](https://superkey.app/)** - Transforms Caps Lock into the Hyperkey, and uses OCR for finding items on the screen.
- **[Homerow](https://www.homerow.app/)** - Provides keyboard-driven navigation
- **[Keyboard Scroller](https://github.com/dexterleng/KeyboardScroller.docs)** - Enables Vim-like scrolling with Hyperkey

### Configured Hyperkey Bindings

Currently, the Hyperkey (Caps Lock) is configured for the following:

#### Navigation

- `Hyper + G` - Seek (Go) - Quick navigation/jump functionality

#### Vim-like Scrolling (via Keyboard Scroller)

- `Hyper + J` - Scroll down
- `Hyper + K` - Scroll up

Note that Keyboard Scroller does allow "Jump Up" and "Jump Down" which in vim-world might be mapped to U and D, but I am already using `Hyper + U` for Aerospace "Utilities" workspace

#### Text Editing (via Superkey Presets)

- `Hyper + Delete` - Forward delete
- `Hyper + V` - Paste without formatting
- `Home` - Move to beginning of line
- `End` - Move to end of line
- `Left Shift + Right Shift` - Toggle Caps Lock

#### Aerospace Workspace Navigation

- `Hyper + T` - Focus workspace T (Terminal)
- `Hyper + Y` - Focus workspace Y (IDE/Development)
- `Hyper + U` - Focus workspace U (Utilities) - Note: conflicts with Jump up
- `Hyper + I` - Focus workspace I (Browsers)
- `Hyper + O` - Focus workspace O (Office)
- `Hyper + P` - Focus workspace P (Productivity)
- `Hyper + [` - Focus workspace [ (Email)
- `Hyper + ]` - Focus workspace ] (Communication)

## Setup Instructions

### Work Mac Setup

1. Install and configure Superkey from [superkey.app](https://superkey.app/)

   **Hyperkey Tab:**

   - Remap key to hyper key: `Caps Lock`
   - Enable "Include shift in hyper key" (checkbox)

   **Presets Tab:**

   - Enable "Left shift + right shift = Caps Lock"
   - Enable "Hyper + delete = forward delete"
   - Enable "Remap paste to paste w/o formatting: Hyper + V"
   - Enable "Home & end operate on lines"

2. Install Homerow from [homerow.app](https://www.homerow.app/)

   - Use for keyboard-driven navigation

3. Install Keyboard Scroller from [github.com/dexterleng/KeyboardScroller.docs](https://github.com/dexterleng/KeyboardScroller.docs)

   - Configure the Vim-like scrolling bindings:
     - Scroll up: `⌃⌥⇧⌘K`
     - Scroll down: `⌃⌥⇧⌘J`

4. Configure Aerospace with the workspace bindings listed above by using the [aerospace.toml](./aerospace/.config/aerospace/aerospace.toml)
