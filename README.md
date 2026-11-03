# KeyBridge

Use your Mac's keyboard and trackpad to control a Windows laptop. **Double-tap Right ⌘** to switch between the two computers. The menu bar shows `⌨︎ Mac` or an orange `⌨︎ → Windows`.

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

Then double-tap **Right ⌘**. Your typing, trackpad, clicks and scrolling now go to Windows. Double-tap it again to go back to the Mac.

## Good to know

- **Modifier keys:** by default ⌘ becomes Ctrl, so ⌘C, ⌘V and ⌘T work as you'd expect. ⌥ becomes Alt and ⌃ becomes the Windows key. You can switch to a layout that follows PC key positions from the menu bar.
- **Trackpad:** click and two-finger click work as left and right click, and two-finger scrolling works too. If the Windows pointer feels too slow or too fast, change **Pointer speed on Windows** in the menu bar. While you're controlling Windows, the Mac pointer stays still where you left it.
- **Gestures:** these work like a Windows touchpad's own gestures. While you're controlling Windows, the Mac ignores them.

  | Gesture | On Windows |
  |---|---|
  | Pinch | Zoom in where you pinch, like Chrome's own pinch. To change the whole page's zoom instead, pick it under **Pinch on Windows** in the menu bar. |
  | 3 or 4 fingers up | Task View (Win+Tab) |
  | 3 or 4 fingers down | Show desktop (Win+D) |
  | 3 fingers left / right | Switch apps (Alt+Tab) |
  | 4 fingers left / right | Switch virtual desktops |

  If you've turned on three-finger drag on your Mac, three-finger swipes are left alone so dragging still works. Use four fingers for the others.
- **Function keys:** hold `fn` to send F1–F12. fn+arrows sends Home/End/Page Up/Page Down, and fn+Delete sends Delete.
- **Safety:** if the connection drops, control switches back to the Mac by itself, and Windows releases any keys or mouse buttons that were held down. Everything you send is encrypted with AES-GCM using a key derived from the pairing code. Without the code, nobody else on the network can see what you send or control the laptop.
- **Sleep and battery:** KeyBridge doesn't keep your Mac awake. It switches back to the Mac when the screen locks or the Mac sleeps, and only reads the trackpad while you're controlling Windows. If Windows is off, it tries to reconnect less and less often, at most every 30 seconds, and tries again right away when the Mac wakes.
- **New pairing code:** run `KeyBridge.exe -reset` from a terminal.
- **Start with Windows:** press Win+R, type `shell:startup`, and put a shortcut to KeyBridge.exe in that folder.
- **Start with your Mac:** add KeyBridge in System Settings → General → Login Items.

## If the cursor feels laggy
KeyBridge can only be as smooth as the network between the two computers. On a good connection, the delay is a few milliseconds.
1. **Use a cable.** Connect the two computers with an Ethernet cable directly (USB adapters work), or plug both into the router.
2. **Turn off Wi-Fi power saving on Windows.** In Device Manager, open your Wi-Fi adapter. Under **Power Management**, untick "Allow the computer to turn off this device". Under **Advanced**, turn off any power-saving option.
3. **Use 5 GHz Wi-Fi** if your router offers it.

## Limitations
- Windows doesn't let normal apps type into admin windows, UAC prompts or the Ctrl+Alt+Del screen. To type into admin apps, right-click KeyBridge.exe and choose **Run as administrator**.
- While a Mac password field has focus, macOS blocks the keyboard from KeyBridge. That's a macOS security feature.
- Media keys (brightness, volume) always act on the Mac. Rotate and smart zoom (double-tap with two fingers) aren't sent to Windows.
- Swipe gestures read the trackpad through a private macOS framework, so a future macOS update could break them.
- If you rebuild the app, macOS may ask for Accessibility permission again. If it doesn't work after a rebuild, remove KeyBridge from the Accessibility list and add it back.

## Building
```
./build.sh
```
This needs Xcode command line tools and Go (`brew install go`). The output goes to `dist/`.
