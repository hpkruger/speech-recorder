#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if pgrep -x SimpleVideoRecorder >/dev/null; then
    print -u2 "Quit Simple Video Recorder before rebuilding so its running signature stays valid."
    exit 1
fi
swift build -c release
./scripts/build-icon.sh
app_path="${SIMPLE_VIDEO_RECORDER_APP_PATH:-/Applications/Simple Video Recorder.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp Assets/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
cp .build/release/SimpleVideoRecorder "$app_path/Contents/MacOS/SimpleVideoRecorder"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SimpleVideoRecorder</string>
<key>CFBundleIdentifier</key><string>local.hanskruger.SimpleVideoRecorder</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Simple Video Recorder</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSCameraUsageDescription</key><string>Show your live mirror and record speech exercises.</string>
<key>NSMicrophoneUsageDescription</key><string>Include your voice in speech exercise recordings.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app_path"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
print "Built: $app_path"
