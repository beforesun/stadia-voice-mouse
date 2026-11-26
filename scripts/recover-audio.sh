#!/bin/sh
set -eu

receiver_url=${STADIA_RECEIVER_URL:-http://192.168.50.85/_status}
driver='/Library/Audio/Plug-Ins/HAL/BlackHole16ch.driver'
log_dir="$HOME/Library/Logs/StadiaVoiceMouse"
stamp_dir="$HOME/Library/Caches/StadiaVoiceMouse"
stamp="$stamp_dir/audio-recover.boot"

if /usr/bin/curl --noproxy '*' -fsS --max-time 2 "$receiver_url" >/dev/null 2>&1; then
  exit 0
fi
if [ ! -d "$driver" ]; then
  exit 0
fi
if /usr/sbin/system_profiler SPAudioDataType 2>/dev/null | /usr/bin/grep -Fq 'BlackHole 16ch:'; then
  exit 0
fi

mkdir -p "$log_dir" "$stamp_dir"
boot_id=$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -n 's/.*sec = \([0-9]*\).*/\1/p')
if [ -z "$boot_id" ] || [ "$(cat "$stamp" 2>/dev/null || true)" = "$boot_id" ]; then
  exit 0
fi
echo "$boot_id" > "$stamp"
echo "$(date '+%Y-%m-%d %H:%M:%S') Receiver unavailable and BlackHole missing; restarting Core Audio" >> "$log_dir/audio-recover.log"
/bin/launchctl kickstart -k system/com.apple.audio.coreaudiod >> "$log_dir/audio-recover.log" 2>&1
