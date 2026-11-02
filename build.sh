#!/bin/sh
# Builds dist/KeyBridge.app (Mac) and dist/KeyBridge.exe (Windows).
set -e
cd "$(dirname "$0")"
rm -rf dist && mkdir -p dist

# Mac menu bar app
app=dist/KeyBridge.app
mkdir -p "$app/Contents/MacOS"
swiftc -O mac/KeyBridge.swift -o "$app/Contents/MacOS/KeyBridge"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>KeyBridge</string>
  <key>CFBundleIdentifier</key><string>local.keybridge</string>
  <key>CFBundleExecutable</key><string>KeyBridge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$app"

# Windows receiver (64-bit; also a 32-bit build for very old laptops)
(cd windows && GOOS=windows GOARCH=amd64 go build -trimpath -o ../dist/KeyBridge.exe .)
(cd windows && GOOS=windows GOARCH=386 go build -trimpath -o ../dist/KeyBridge-32bit.exe .)

echo "Built:"; ls -1 dist
