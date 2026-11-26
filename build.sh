#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) MacTools.app and MacTools.zip in ./dist
set -euo pipefail
cd "$(dirname "$0")"
SRC=(Core.swift DevTools.swift UtilTools.swift Dashboard.swift main.swift)
APP=dist/MacTools.app
VERSION=${1:-1.0.0}

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos14 "${SRC[@]}" -o dist/MacTools-$arch
done
lipo -create dist/MacTools-arm64 dist/MacTools-x86_64 -output "$APP/Contents/MacOS/MacTools"
rm dist/MacTools-arm64 dist/MacTools-x86_64

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacTools</string>
<key>CFBundleIdentifier</key><string>io.github.mactools</string>
<key>CFBundleName</key><string>MacTools</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF

codesign -s - --force "$APP"
(cd dist && ditto -c -k --keepParent MacTools.app MacTools.zip)
echo "Built dist/MacTools.app and dist/MacTools.zip"
