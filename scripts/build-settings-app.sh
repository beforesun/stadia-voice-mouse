#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
swift build -c release

app_dir="$project_dir/dist/Stadia Controller Settings.app"
macos_dir="$app_dir/Contents/MacOS"
resources_dir="$app_dir/Contents/Resources"
mkdir -p "$macos_dir" "$resources_dir"
cp "$project_dir/assets/StadiaVoiceMouseIcon.icns" "$resources_dir/StadiaVoiceMouseIcon.icns"
if [ "${1:-}" = "--universal" ]; then
  swift build -c release --triple arm64-apple-macosx13.0 --build-path .build-arm64
  lipo -create .build/release/stadia-voice-mouse \
    .build-arm64/arm64-apple-macosx/release/stadia-voice-mouse \
    -output "$macos_dir/stadia-voice-mouse"
else
  cp .build/release/stadia-voice-mouse "$macos_dir/stadia-voice-mouse"
fi
cat > "$macos_dir/launcher" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/stadia-voice-mouse" --settings
EOF
chmod +x "$macos_dir/launcher" "$macos_dir/stadia-voice-mouse"
cat > "$app_dir/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Stadia Controller Settings</string>
  <key>CFBundleDisplayName</key><string>Stadia 手柄设置</string>
  <key>CFBundleIdentifier</key><string>com.beforesun.stadiavoicemouse.settings</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>StadiaVoiceMouseIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
EOF
printf 'Created %s\n' "$app_dir"
