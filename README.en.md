# ZestCaps

> **[简体中文](README.md) | English**

> v0.3.3 — [MIT License](LICENSE)

[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A macOS-style CapsLock input method switching tool: short-press to toggle between Chinese and English, long-press to toggle CapsLock. It also bundles everyday utilities such as an input state indicator, plain-text paste, and region screenshot. Built with AutoHotkey v2, portable and no installation required.

## Background

The CapsLock-based input method switching on macOS has always been a great experience, but there was no good equivalent on Windows. So I built this CapsLock input switching tool with the help of AI, and packed in handy daily utilities such as screenshot and plain-text paste.

## Features

### 1. CapsLock Enhancement

- **Short press** (released within 0.3 s): switch between Chinese and English input methods
- **Long press** (hold over 0.3 s): toggle CapsLock on/off

### 2. Input State Indicator

- While the cursor is in a text-input context, shows the current input method state `中` / `英` / `A` in real time next to the cursor
- Based on the `WM_IME_CONTROL` message for **real-time detection** of the true state, no manual syncing, compatible with TSF input methods such as WeType
- **Remembers the input method per window** and restores it automatically when switching windows
- State caching + repaint only on change, flicker-free and low resource usage
- Toggleable in the settings window

### 3. Plain-Text Paste (Ctrl+Shift+V)

- Automatically strips clipboard formatting and leading/trailing whitespace on paste
- Toggleable in the settings window

### 4. Region Screenshot (F1)

- Gray translucent mask with a cut-out highlight on the selection + sky-blue border; hover to snap to windows, drag to select any rectangular region
- Double-click the selection to copy it to the clipboard and close, or annotate/save/pin/copy via the toolbar; `Esc` or right-click to cancel, auto-cancel on timeout
- After confirming, an **annotation editor** opens automatically: rectangle / arrow / ellipse / mosaic, with clear, and supports copy/save/pin
- One-key **pin** (always-on-top, draggable, right-click to close), copy, or save as PNG
- Toggleable in the settings window

### 5. Startup Splash Animation

- Shows a dark rounded card at startup: title + `中/英/A` chips cycling through colors (green → blue → orange) at the bottom
- Fades in and out and closes automatically, timer-driven, does not block hotkey registration
- Drawn with GDI+ layered windows, requires no image assets

### 6. Startup Options

- **Run at startup**: implemented via a shortcut in the Start menu startup folder, one-click toggle in the settings window; disabled by default
- **Create desktop shortcut**: creates `ZestCaps.lnk` on the desktop, one-click toggle in the settings window; disabled by default (check to create, uncheck to delete)

### 7. Scheduled Recycle Bin Cleanup

- Automatically empties, at a fixed daily time, items in the Recycle Bin whose **deletion time exceeds the retention days** (a "keep recent N days" policy)
- Configurable in the settings window: toggle, retention days (7 / 15 / 30 days), and daily execution time (hour/minute steppers, 24-hour format)
- The timer is a one-shot dynamic schedule that wakes only near the execution time, with zero load when idle
- Disabled by default

### 8. GitHub Auto-Update (compiled builds only)

- The settings "About" page offers a "Check for Updates" button and an "auto check for updates at startup" toggle; clicking asynchronously queries the latest GitHub release
- Semantic-version comparison + SHA256 verification, then download with a delayed auto-replace and restart after confirmation
- Self-replaces via the running executable's real path, so it works even if you rename the exe
- Takes effect only in compiled builds; source runs show a "not available" notice

## Input Method Detection Principle

```text
Real-time query (WM_IME_CONTROL, primary) → every 80 ms, compatible with TSF input methods such as WeType
   ↓ on query failure
Per-window state cache (Map, capped at 200 entries with auto-cleanup)
   ↓ new window without cache
Keyboard layout fallback (non-Chinese layout → English)
```

## File Structure

```text
src\
├── Main.ahk            Main entry: loads modules (fixed CapsLock hotkey + configurable hotkey registration)
├── config.ini          Feature toggles and configurable hotkeys (written back on settings save)
├── Config\
│   └── Config.ahk      Configuration (params & toggles, read from config.ini)
├── DebugLog\
│   ├── DebugLog.ahk    Debug logging
│   └── GlobalError.ahk Global uncaught-error handler (logs, prevents dialogs)
├── Startup\
│   └── Startup.ahk     Run-at-startup detection and switching
├── DesktopShortcut\
│   └── DesktopShortcut.ahk  Desktop shortcut create/delete
├── Splash\
│   └── Splash.ahk      Startup splash animation (GDI+ layered window, pure code)
├── Indicator\
│   ├── IME.ahk         Input method Chinese/English state detection (WM_IME_CONTROL)
│   └── Indicator.ahk   Input state indicator (GUI, cursor-following, flicker-proof cache)
├── InputSwitch\
│   └── CapsLock.ahk    CapsLock behavior (short/long press dispatch, modifier release)
├── Clipboard\
│   ├── Clipboard.ahk   Clipboard module entry (plain-text paste)
│   └── PastePlain.ahk  Plain-text paste (default Ctrl+Shift+V, configurable)
├── RecycleBin\
│   └── RecycleBin.ahk  Scheduled recycle bin cleanup (keep N days, daily fixed time)
├── Hotkeys\
│   └── Hotkeys.ahk     Configurable hotkeys (read/register/validate, stored in [Hotkeys])
├── Settings\
│   └── Settings.ahk    Settings window (feature toggles + hotkey config)
├── Updater\
│   └── Updater.ahk     GitHub auto-update (compiled only: check/download/SHA256 verify/self-replace)
├── Screenshot\
│   ├── Screenshot.ahk  Region screenshot main flow (selection overlay / capture / annotation editor)
│   ├── Editor.ahk      Annotation editor (drawing tools / clear / pin / copy / save)
│   ├── Pin.ahk         Screenshot pinning (always-on-top / drag / right-click close)
│   └── Common\
│       ├── Overlay.ahk     Shared overlay component (mask cut-out + 4 borders)
│       └── ToolbarUI.ahk   Shared toolbar component (color swatches / flat buttons / hover)
├── Common\
│   └── Gdip_All_v2.ahk Gdip library (screenshot/splash; the only third-party dependency)
└── TrayMenu\
    └── TrayMenu.ahk    Tray menu initialization (settings / restart / exit)
build.bat               Build script (outputs output\zestcaps.exe)
```

> Convention: the fixed CapsLock hotkey is defined in `src\Main.ahk`; other hotkeys are dynamically registered (configurable) in `src\Hotkeys\Hotkeys.ahk`; each feature lives in `src\<module-name>\` for easy extension and maintenance.

## Configuration

- `config.ini`: feature toggles and configurable hotkeys
  - Initial feature toggle states (`IndicatorEnabled`, `PastePlainEnabled`, `ScreenshotEnabled`, `SplashEnabled`, `StartupEnabled`, `DesktopShortcutEnabled`, `RecycleBinEnabled`, `AutoUpdateEnabled`), written back automatically when saving in the settings window
  - Configurable hotkeys (`[Hotkeys]` section: `PastePlain`, `Screenshot`), fill in AHK-native format directly in the settings window "hotkeys" text boxes (e.g. `^v`, `F1`); effective after save & restart
- `src\Config\Config.ahk`: remaining hardcoded parameters
  - Menu text (`MENU_TITLE`, `MENU_SETTINGS`, `MENU_RESTART`, `MENU_EXIT`)
  - Indicator text/colors/size/offset/font (`IND_*`)
  - CapsLock short/long press thresholds (`CAPS_*`)
  - Recycle bin retention days / execution time (`RB_*`, `RecycleBinKeepDays`, `RecycleBinTime`)
  - Splash size/duration/colors (`SPLASH_*`)
  - Screenshot / selection / annotation-editor parameters (`SCREENSHOT_FILENAME`, `SEL_*`, `EDIT_*`, `SCREENSHOT_TIMEOUT_MS`, etc.)

Restart the script after modifying.

## Install & Usage

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/) or later
2. Clone or download this repository
3. Double-click `src\Main.ahk` to run
4. Right-click the tray icon → "Settings..." or control any feature toggle and hotkey in the settings window

## Build

Run `build.bat` to compile the script into a standalone `output\zestcaps.exe` (requires AutoHotkey v2 and the Ahk2Exe compiler).

## License

This project is released under the [MIT License](LICENSE), allowing free use, modification, and distribution. See the [LICENSE](LICENSE) file for details.