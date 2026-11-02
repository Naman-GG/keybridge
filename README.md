# KeyBridge

Use your Mac's built-in keyboard to type on a Windows laptop. **Double-tap Right ⌘** to switch where your typing goes. The menu bar shows `⌨︎ Mac` or an orange `⌨︎ → Windows`.

Both computers must be on the same network (same Wi-Fi is fine).

## Setup

### 1. Windows laptop
1. On the laptop, download `KeyBridge.exe` from the [latest release](https://github.com/Naman-GG/keybridge/releases/latest). Use `KeyBridge-32bit.exe` if the laptop runs 32-bit Windows.
2. Double-click it. If SmartScreen warns you, click **More info → Run anyway**. If Windows Firewall asks, allow it on **Private networks**.
3. The window shows an **Address** and a **Pairing code**. Leave the window open.

### 2. Mac
1. Download `KeyBridge-mac.zip` from the [latest release](https://github.com/Naman-GG/keybridge/releases/latest), unzip it, and move KeyBridge.app to `/Applications`. The app isn't notarized, so the first time you open it, right-click it and choose **Open**. Or build it yourself with `./build.sh`.
2. When macOS asks, allow KeyBridge in **System Settings → Privacy & Security → Accessibility**. You don't need to restart the app; it picks up the permission within a couple of seconds.
3. Enter the address and pairing code from the Windows window.

Then double-tap **Right ⌘** and type. Double-tap it again to go back to the Mac.

## Good to know

- **Modifier keys:** by default ⌘ becomes Ctrl, so ⌘C, ⌘V and ⌘T work as you'd expect. ⌥ becomes Alt and ⌃ becomes the Windows key. You can switch to a layout that follows PC key positions from the menu bar.
- **Function keys:** hold `fn` to send F1–F12. fn+arrows sends Home/End/Page Up/Page Down, and fn+Delete sends Delete.
- **Safety:** if the connection drops, typing switches back to the Mac by itself, and Windows releases any keys that were held down. Keystrokes are encrypted with AES-GCM using a key derived from the pairing code. Without the code, nobody else on the network can read your keystrokes or type into the laptop.
- **New pairing code:** run `KeyBridge.exe -reset` from a terminal.
- **Start with Windows:** press Win+R, type `shell:startup`, and put a shortcut to KeyBridge.exe in that folder.
- **Start with your Mac:** add KeyBridge in System Settings → General → Login Items.

## Limitations
- Windows doesn't let normal apps type into admin windows, UAC prompts or the Ctrl+Alt+Del screen. To type into admin apps, right-click KeyBridge.exe and choose **Run as administrator**.
- While a Mac password field has focus, macOS blocks the keyboard from KeyBridge. That's a macOS security feature.
- Media keys (brightness, volume) always act on the Mac.
- If you rebuild the app, macOS may ask for Accessibility permission again. If it doesn't work after a rebuild, remove KeyBridge from the Accessibility list and add it back.

## Building
```
./build.sh
```
This needs Xcode command line tools and Go (`brew install go`). The output goes to `dist/`.
