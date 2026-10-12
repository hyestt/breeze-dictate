#!/bin/zsh
# 建置 build/BreezeDictate.app（arm64、macOS 14+、ad-hoc 簽署）與 build/BreezeDictate-<版本>.zip。
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$ROOT/build"
APP="$BUILD/BreezeDictate.app"
rm -rf "$APP" "$BUILD/icon"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/icon/AppIcon.iconset"

echo "編譯 Swift…"
# 此環境的 SwiftUI 巨集外掛只在 Xcode 內，原始碼避免使用 @State 等巨集。
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/BreezeDictate" \
  app/Sources/*.swift app/Sources/Views/*.swift

echo "產生圖示…"
cat > "$BUILD/icon/make_icon.swift" <<'SWIFT'
import AppKit

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.06
    let box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: box, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(starting: NSColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.25, blue: 0.70, alpha: 1))!.draw(in: bg, angle: -90)

    NSColor.white.setFill()
    NSColor.white.setStroke()
    let mw = s * 0.20, mh = s * 0.34
    let mic = NSBezierPath(roundedRect: NSRect(x: (s - mw) / 2, y: s * 0.42, width: mw, height: mh),
                           xRadius: mw / 2, yRadius: mw / 2)
    mic.fill()
    let lw = s * 0.035
    let arc = NSBezierPath()
    arc.lineWidth = lw
    arc.lineCapStyle = .round
    arc.appendArc(withCenter: NSPoint(x: s / 2, y: s * 0.52), radius: s * 0.19, startAngle: 180, endAngle: 360)
    arc.stroke()
    let stem = NSBezierPath()
    stem.lineWidth = lw
    stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: s / 2, y: s * 0.33))
    stem.line(to: NSPoint(x: s / 2, y: s * 0.25))
    stem.move(to: NSPoint(x: s * 0.40, y: s * 0.25))
    stem.line(to: NSPoint(x: s * 0.60, y: s * 0.25))
    stem.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512),
                   ("512x512@2x", 1024)] {
    try draw(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
SWIFT
swiftc -o "$BUILD/icon/make_icon" "$BUILD/icon/make_icon.swift"
"$BUILD/icon/make_icon" "$BUILD/icon/AppIcon.iconset"
iconutil -c icns "$BUILD/icon/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "組裝 App…"
cp app/Resources/* "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.hyestt.breeze-dictate</string>
  <key>CFBundleName</key><string>BreezeDictate</string>
  <key>CFBundleDisplayName</key><string>BreezeDictate</string>
  <key>CFBundleExecutable</key><string>BreezeDictate</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>BreezeDictate 需要麥克風，才能把你說的話轉成文字。</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --deep -s - "$APP"
codesign -v "$APP"

ZIP="$BUILD/BreezeDictate-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
rm -rf "$BUILD/icon"
echo "完成：$APP"
echo "完成：$ZIP"
