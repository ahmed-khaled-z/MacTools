# MacTools 🔧

تطبيق صغير لشريط القوائم في الماك (menu bar) فيه 12 أداة مفيدة، بواجهة عربية.

A tiny macOS menu-bar app with 12 handy tools (Arabic UI). Native Swift/SwiftUI, no dependencies.

## الأدوات / Tools

| | |
|---|---|
| 🧹 **تنظيف المساحة** — كاش، لوج، سلة المهملات، DerivedData، npm/Yarn، brew cleanup | ⬇️ **تحميل فيديو / صوت** — يوتيوب، تيك توك، إنستجرام، فيسبوك، X (عبر yt-dlp) |
| 🔤 **نص من الشاشة** — OCR عربي وإنجليزي بدون إنترنت | 🌐 **البورتات** — اعرض البورتات المفتوحة واقفلها (Metro / Expo / Vite) |
| 📦 **صياد node_modules** — دوّر في `~/projects` وامسح node_modules و Pods | 📱 **تنظيف Simulator** — simulators قديمة، DeviceSupport، كاش |
| ☕ **منع النوم** — caffeinate بمؤقت | 📋 **سجل الحافظة** — آخر 30 حاجة نسختها |
| 📶 **الشبكة** — IP محلي وعام واختبار سرعة | 🔳 **QR Code** — من الحافظة لصورة |
| 🎛️ **مفاتيح سريعة** — الوضع الداكن، أيقونات الديسكتوب، الملفات المخفية، إخراج الهاردات، قفل الشاشة | 🔑 **مولّد باسوردات** |

## التثبيت / Install

1. نزّل `MacTools.zip` من [Releases](../../releases/latest) وفكّه، وانقل `MacTools.app` لفولدر Applications.
2. التطبيق مش موقّع من Apple، فأول مرة: **كليك يمين ← Open ← Open**.
   أو من التيرمنال:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacTools.app
   ```
3. لأداة التحميل محتاج [Homebrew](https://brew.sh) و:
   ```bash
   brew install yt-dlp ffmpeg
   ```

يشتغل على macOS 14 أو أحدث (Apple Silicon و Intel).

**ملاحظات:**
- عشان التنظيف يشوف سلة المهملات: System Settings ← Privacy & Security ← Full Disk Access ← ضيف MacTools.
- عشان يفتح مع تشغيل الماك: System Settings ← General ← Login Items.
- المسح في أداة التنظيف نهائي (مش بيروح سلة المهملات).

## Build from source

```bash
./build.sh 1.0.0   # → dist/MacTools.app + dist/MacTools.zip (universal)
```
