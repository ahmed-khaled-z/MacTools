# MacTools 🔧

A tiny macOS menu-bar app with 12 handy tools. Native Swift/SwiftUI, no dependencies. (The app's interface is in Arabic.)

## Tools

| | |
|---|---|
| 🧹 **Disk cleanup**: app caches, logs, Trash, Xcode DerivedData, npm/Yarn caches, `brew cleanup` | ⬇️ **Video / audio downloader**: YouTube, TikTok, Instagram, Facebook, X and more (via yt-dlp) |
| 🔤 **Text from screen**: offline OCR for Arabic and English | 🌐 **Ports**: list listening ports and kill them (Metro, Expo, Vite tagged) |
| 📦 **node_modules hunter**: find and delete `node_modules` and `Pods` under `~/projects` | 📱 **Simulator cleanup**: unavailable simulators, iOS DeviceSupport, caches |
| ☕ **Keep awake**: `caffeinate` with a timer | 📋 **Clipboard history**: last 30 copied items |
| 📶 **Network**: local and public IP, speed test | 🔳 **QR code**: turn clipboard text into a QR image |
| 🎛️ **Quick toggles**: dark mode, desktop icons, hidden files, eject disks, lock screen | 🔑 **Password generator** |

## Install

1. Download `MacTools.zip` from [Releases](../../releases/latest), unzip it, and move `MacTools.app` to Applications.
2. The app isn't notarized by Apple, so the first time: **right-click → Open → Open**.
   Or from Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacTools.app
   ```
3. The downloader needs [Homebrew](https://brew.sh) and:
   ```bash
   brew install yt-dlp ffmpeg
   ```

Requires macOS 14 or later (Apple Silicon and Intel).

**Notes**
- To let the cleaner see the Trash: System Settings → Privacy & Security → Full Disk Access → add MacTools.
- To start it at login: System Settings → General → Login Items.
- Cleanup deletes files permanently (they don't go to the Trash).

## Build from source

```bash
./build.sh 1.0.0   # → dist/MacTools.app + dist/MacTools.zip (universal)
```
