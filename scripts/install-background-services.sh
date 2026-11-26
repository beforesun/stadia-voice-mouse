#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
user_name=${SUDO_USER:-$(id -un)}
user_home=$(dscl . -read "/Users/$user_name" NFSHomeDirectory | awk '{print $2}')
user_id=$(id -u "$user_name")
mac_ip=$(/usr/sbin/ipconfig getifaddr en0)
controller_ip=${STADIA_CONTROLLER_IP:-192.168.50.189}
router_ip=${STADIA_ROUTER_IP:-192.168.50.1}
runtime_dir='/Library/Application Support/StadiaVoiceMouse'
log_dir='/Library/Logs/StadiaVoiceMouse'
stage_dir="$project_dir/dist/background"
daemon_plist='/Library/LaunchDaemons/com.beforesun.stadiacast.plist'
agent_plist="$user_home/Library/LaunchAgents/com.beforesun.stadia-bridge.plist"
audio_agent_plist="$user_home/Library/LaunchAgents/com.beforesun.stadia-audio-recover.plist"
source_venv="$user_home/.local/share/uv/tools/stadiacast"
source_python=$(/usr/bin/python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$user_home/.local/share/uv/python/cpython-3.13-macos-x86_64-none")
bridge_app="$user_home/Applications/Stadia Voice Mouse Bridge.app"
bridge_binary="$bridge_app/Contents/MacOS/stadia-voice-mouse"

case "$mac_ip:$controller_ip:$router_ip" in
  *[!0-9.:]*) echo 'Only IPv4 addresses are supported by this installer.' >&2; exit 1 ;;
esac
test -x "$project_dir/.build/release/stadia-voice-mouse"
test -x "$source_python/bin/python3.13"
test -d "$source_venv/lib/python3.13/site-packages"
test -x "$user_home/.local/bin/ffmpeg"

prepare() {
  mkdir -p "$stage_dir"
  cat > "$stage_dir/com.beforesun.stadiacast.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.beforesun.stadiacast</string>
  <key>ProgramArguments</key><array>
    <string>$runtime_dir/venv/bin/python</string><string>-m</string><string>stadiacast</string>
    <string>--preset</string><string>live</string>
    <string>--bind</string><string>$mac_ip</string>
    <string>--advertise-ip</string><string>$mac_ip</string>
    <string>--controller-ip</string><string>$controller_ip</string>
    <string>--dns-upstream</string><string>$router_ip</string>
    <string>--dns-redirect</string><string>time.google.com,connectivitycheck.gstatic.com,clients3.google.com</string>
    <string>--stadiaconfig</string><string>json:{}</string>
    <string>--mic</string><string>ptt</string>
    <string>--mic-device</string><string>BlackHole 16ch</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$runtime_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>WorkingDirectory</key><string>$log_dir</string>
  <key>StandardOutPath</key><string>$log_dir/receiver.out.log</string>
  <key>StandardErrorPath</key><string>$log_dir/receiver.err.log</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>15</integer>
</dict></plist>
EOF
  cat > "$stage_dir/com.beforesun.stadiacast-test.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.beforesun.stadiacast-test</string>
  <key>ProgramArguments</key><array>
    <string>$runtime_dir/venv/bin/python</string><string>-m</string><string>stadiacast</string>
    <string>--bind</string><string>127.0.0.1</string>
    <string>--https-port</string><string>1443</string>
    <string>--http-ports</string><string>18008</string>
    <string>--controller-ip</string><string>$controller_ip</string>
    <string>--stadiaconfig</string><string>json:{}</string>
    <string>--no-sntp</string>
    <string>--mic</string><string>off</string>
    <string>--mic-device</string><string>BlackHole 16ch</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$runtime_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>WorkingDirectory</key><string>$log_dir</string>
  <key>StandardOutPath</key><string>$log_dir/test.out.log</string>
  <key>StandardErrorPath</key><string>$log_dir/test.err.log</string>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
  cat > "$stage_dir/com.beforesun.stadia-bridge.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.beforesun.stadia-bridge</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/open</string><string>-W</string><string>-a</string><string>$bridge_app</string><string>--args</string>
    <string>--url</string><string>http://$mac_ip/_events</string>
    <string>--controller</string><string>c0</string>
    <string>--voice-keycode</string><string>54</string>
    <string>--keyboard-input</string><string>Built-in Microphone</string>
    <string>--controller-input</string><string>BlackHole 16ch</string>
  </array>
  <key>WorkingDirectory</key><string>$project_dir</string>
  <key>StandardOutPath</key><string>$user_home/Library/Logs/StadiaVoiceMouse/bridge.out.log</string>
  <key>StandardErrorPath</key><string>$user_home/Library/Logs/StadiaVoiceMouse/bridge.err.log</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>15</integer>
</dict></plist>
EOF
  cat > "$stage_dir/com.beforesun.stadia-audio-recover.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.beforesun.stadia-audio-recover</string>
  <key>ProgramArguments</key><array><string>$user_home/Library/Application Support/StadiaVoiceMouse/recover-audio.sh</string></array>
  <key>EnvironmentVariables</key><dict><key>STADIA_RECEIVER_URL</key><string>http://$mac_ip/_status</string></dict>
  <key>StartInterval</key><integer>60</integer>
  <key>StandardOutPath</key><string>$user_home/Library/Logs/StadiaVoiceMouse/audio-recover.out.log</string>
  <key>StandardErrorPath</key><string>$user_home/Library/Logs/StadiaVoiceMouse/audio-recover.err.log</string>
</dict></plist>
EOF
  for file in "$stage_dir"/*.plist; do plutil -lint "$file"; done
  echo "Prepared launchd files in $stage_dir"
}

if [ "${1:-}" = '--prepare' ]; then prepare; exit 0; fi
if [ "${1:-}" = '--install-audio-recovery' ]; then
  prepare
  mkdir -p "$user_home/Library/Application Support/StadiaVoiceMouse" "$user_home/Library/LaunchAgents" "$user_home/Library/Logs/StadiaVoiceMouse"
  cp "$project_dir/scripts/recover-audio.sh" "$user_home/Library/Application Support/StadiaVoiceMouse/recover-audio.sh"
  chmod 755 "$user_home/Library/Application Support/StadiaVoiceMouse/recover-audio.sh"
  cp "$stage_dir/com.beforesun.stadia-audio-recover.plist" "$audio_agent_plist"
  launchctl bootout "gui/$user_id/com.beforesun.stadia-audio-recover" 2>/dev/null || true
  launchctl bootstrap "gui/$user_id" "$audio_agent_plist"
  echo 'Installed BlackHole startup recovery check.'
  exit
fi
if [ "${1:-}" = '--install-bridge' ]; then
  prepare
  mkdir -p "$bridge_app/Contents/MacOS" "$user_home/Library/LaunchAgents" "$user_home/Library/Logs/StadiaVoiceMouse"
  launchctl bootout "gui/$user_id/com.beforesun.stadia-bridge" 2>/dev/null || true
  for pid in $(pgrep -u "$user_id" -f "^$bridge_binary --url" || true); do
    kill -TERM "$pid"
  done
  cp "$project_dir/.build/release/stadia-voice-mouse" "$bridge_binary"
  cat > "$bridge_app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.beforesun.stadia-voice-mouse.bridge</string>
  <key>CFBundleName</key><string>Stadia Voice Mouse Bridge</string>
  <key>CFBundleExecutable</key><string>stadia-voice-mouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
  codesign --force --sign - "$bridge_app"
  cp "$stage_dir/com.beforesun.stadia-bridge.plist" "$agent_plist"
  launchctl bootstrap "gui/$user_id" "$agent_plist"
  "$0" --install-audio-recovery
  echo "Installed bridge app at $bridge_app"
  exit
fi
if [ "${1:-}" != '--root-install' ]; then
  prepare
  echo 'Installing requires one administrator password in this Terminal.'
  sudo "$0" --root-install
  exit
fi
test "$(id -u)" = 0
test -n "${SUDO_USER:-}"

mkdir -p "$runtime_dir" "$runtime_dir/bin" "$log_dir" "$user_home/Library/Logs/StadiaVoiceMouse"
ditto "$source_python" "$runtime_dir/python"
"$runtime_dir/python/bin/python3.13" -m venv "$runtime_dir/venv"
ditto "$source_venv/lib/python3.13/site-packages" "$runtime_dir/venv/lib/python3.13/site-packages"
cp "$user_home/.local/bin/ffmpeg" "$runtime_dir/bin/ffmpeg"
chown -R root:wheel "$runtime_dir" "$log_dir"
chmod -R go-w "$runtime_dir" "$log_dir"
"$runtime_dir/venv/bin/python" -m stadiacast --version

test_plist="$stage_dir/com.beforesun.stadiacast-test.plist"
cp "$test_plist" '/Library/LaunchDaemons/com.beforesun.stadiacast-test.plist'
chown root:wheel '/Library/LaunchDaemons/com.beforesun.stadiacast-test.plist'
chmod 644 '/Library/LaunchDaemons/com.beforesun.stadiacast-test.plist'
launchctl bootstrap system '/Library/LaunchDaemons/com.beforesun.stadiacast-test.plist'
sleep 3
if ! curl -fsS --max-time 3 http://127.0.0.1:18008/_status | /usr/bin/python3 -c 'import json,sys; s=json.load(sys.stdin); d=s.get("mic_device") or {}; sys.exit(0 if d.get("name")=="BlackHole 16ch" and not d.get("error") else 1)'; then
  echo "Root daemon audio test failed. See $log_dir/test.err.log" >&2
  launchctl bootout system/com.beforesun.stadiacast-test || true
  exit 1
fi
launchctl bootout system/com.beforesun.stadiacast-test
echo 'Root daemon and BlackHole test passed.'

cp "$stage_dir/com.beforesun.stadiacast.plist" "$daemon_plist"
chown root:wheel "$daemon_plist"
chmod 644 "$daemon_plist"

# Stop only the currently known terminal-launched receiver before claiming ports 53/123/443.
for pid in $(pgrep -f "$source_venv/bin/python $user_home/.local/bin/stadiacast --preset live" || true); do
  kill -TERM "$pid"
done
sleep 2
launchctl bootstrap system "$daemon_plist"
sleep 3
if ! curl -fsS --max-time 3 "http://$mac_ip/_status" | /usr/bin/python3 -c 'import json,sys; s=json.load(sys.stdin); d=s.get("mic_device") or {}; sys.exit(0 if d.get("name")=="BlackHole 16ch" and not d.get("error") else 1)'; then
  echo "Background receiver did not start. See $log_dir/receiver.err.log" >&2
  exit 1
fi
echo 'Background receiver is responding.'

mkdir -p "$user_home/Library/LaunchAgents"
for pid in $(pgrep -u "$user_id" -f "$project_dir/.build/release/stadia-voice-mouse --url" || true); do
  kill -TERM "$pid"
done
sudo -u "$user_name" "$0" --install-bridge
sleep 2
launchctl asuser "$user_id" launchctl print "gui/$user_id/com.beforesun.stadia-bridge" | head -18
echo 'Background installation complete.'
