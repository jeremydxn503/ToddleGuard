# ToddleGuard

Menu bar utility that turns your MacBook into “kid is in my lap” mode: while Kid Mode is on, keyboard typing and trackpad clicks/scrolls are blocked so a toddler can’t navigate your Mac. Unlock with a deliberate shortcut.

## Features

- Menu bar lock icon with **Turn Kid Mode On/Off**
- System-wide input blocking via `CGEvent` tap (keyboard + mouse/trackpad clicks, drags, scroll)
- Unlock while Kid Mode is on:
  1. **Caps Lock twice within 3 seconds**
  2. **⌘⌥⇧K** (Command-Option-Shift-K)
- First-run onboarding and menu item to grant **Accessibility** permission
- **Open at Login** toggle (macOS Login Item via `SMAppService`)

## Requirements

- macOS 13 or later
- Xcode (or Command Line Tools with full macOS SDK) to build
- **Accessibility** permission for ToddleGuard (required for the event tap)

## Build and run

```bash
cd ~/Projects/ToddleGuard
xcodebuild -scheme ToddleGuard -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/ToddleGuard.app
```

Or open `ToddleGuard.xcodeproj` in Xcode and press Run.

The app is a menu bar agent (`LSUIElement`): it does not show a Dock icon. Look for the lock icon / **Toddle** in the menu bar.

## Accessibility permission

ToddleGuard checks `AXIsProcessTrusted()` for **this running process**. System Settings can show a ToddleGuard toggle ON while the process still reports untrusted if the enabled entry is an **older build** (different path or code signature).

### First-time grant

1. Launch ToddleGuard.
2. In Setup (or **Grant Accessibility…**), click **Open System Settings**.
3. In **System Settings → Privacy & Security → Accessibility**, enable **ToddleGuard**.
4. Return to ToddleGuard (or click **Check Again**). If it stays orange, use the steps below.

### If Settings says enabled but ToddleGuard still says “Needs Accessibility”

This is the usual Debug-build failure mode. Debug builds are **ad-hoc signed** (`CODE_SIGN_IDENTITY = "-"`). macOS pins Accessibility to the app’s **code identity** (designated requirement / CDHash). Every rebuild changes that identity, so an old toggle no longer covers the new binary even when the name still says ToddleGuard.

Do this exactly:

1. Quit ToddleGuard (menu → **Quit ToddleGuard**).
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Select every **ToddleGuard** / **Toddle** row and remove it (−).
4. Optional cleanup (safe for this app only):

   ```bash
   tccutil reset Accessibility com.jeremy.ToddleGuard
   ```

5. Launch **only** the copy you intend to use:

   ```bash
   open /Users/jeremy/Projects/ToddleGuard/build/Build/Products/Debug/ToddleGuard.app
   ```

6. In Setup, click **Copy Path** (or **Reveal in Finder**). Confirm the path matches the app you just opened.
7. In Accessibility, click **+**, press **⌘⇧G**, paste that path, add it, and turn the toggle **ON**.
8. Click **Quit & Relaunch** in Setup (or quit and `open` the same path again).
9. Status should turn green / menu should say **Status: Ready**.

### Stable signing (optional, avoids re-granting after every rebuild)

Ad-hoc signing cannot keep a stable designated requirement across rebuilds. Options:

- **Apple Development / Developer ID** team in Xcode (best if you have a membership).
- **Local self-signed code-signing certificate** used as `CODE_SIGN_IDENTITY` (permissions survive rebuilds on your Mac only). See [preserving TCC with a stable cert](https://evoleinik.com/posts/macos-dev-signing-preserve-permissions/).

Until then, prefer one install path and re-add that exact `.app` after rebuilds, or reset with `tccutil` as above.

Without Accessibility trust, Kid Mode cannot start.

## Open at Login

Use **Open at Login** in the ToddleGuard menu. That registers a standard macOS Login Item (`SMAppService.mainApp`), which is the most reliable approach for a menu bar app on modern macOS.

You can also manage it under **System Settings → General → Login Items**.

Enable Open at Login after you have placed/built the `.app` you intend to keep using (for example after copying it to `/Applications`).

## Unlock methods (while Kid Mode is on)

| Method | Action |
|--------|--------|
| Caps Lock double-tap | Press **Caps Lock** twice within **3.0 seconds** |
| Hotkey | Press **⌘ ⌥ ⇧ K** together |

The menu **Turn Kid Mode Off** also works while Kid Mode is on: clicks inside the menu bar strip are allowed so you can still use the ToddleGuard status item. Prefer the keyboard unlocks if a toddler is hammering the trackpad.

## Limitations

- **Accessibility** is mandatory. Secure Input (password fields, some browsers / 1Password) can prevent event taps from seeing keystrokes until Secure Input ends.
- Does not block the Touch Bar, power button, or Force Quit (⌘⌥⎋ may still be partially restricted depending on what the tap receives).
- Cursor movement is intentionally allowed; clicks, drags, and scroll are blocked.
- Caps Lock unlock swallows Caps Lock events (system Caps Lock state should not toggle during unlock attempts).
- Unsigned/ad-hoc local builds: Gatekeeper may require a right-click → Open the first time if you move the app around; Accessibility grants often need re-adding after rebuilds.
- Not a security sandbox against a determined adult; it is toddler-proofing.

## Project layout

- `ToddleGuard/` — Swift sources (AppKit menu bar + onboarding + `CGEvent` tap)
- `ToddleGuard.xcodeproj` — Xcode project
