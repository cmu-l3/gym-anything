#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Export: Export Rename ==="

apt-get update -qq && apt-get install -y -qq xdotool wmctrl || true

wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
  su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
  sleep 1
fi

# No automatic export; agent should have exported to export.jpg. Just ensure focus and close.

if [ -f "/home/ga/Desktop/export.jpg" ]; then
  chown ga:ga /home/ga/Desktop/export.jpg
  echo "✅ export.jpg present on Desktop."
else
  echo "⚠️ export.jpg missing on Desktop."
fi

su - ga -c "DISPLAY=:1 xdotool key ctrl+q" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1

echo "✅ GIMP closed."
