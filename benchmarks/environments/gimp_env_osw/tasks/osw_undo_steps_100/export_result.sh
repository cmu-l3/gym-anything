#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Export: Persist Undo Steps Setting ==="

apt-get update -qq && apt-get install -y -qq xdotool wmctrl || true

wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
  su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
  sleep 1
fi

# Export canvas for audit trail
su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+e" || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool type osw_undo_canvas_export" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 2

if [ -f "/home/ga/Desktop/osw_undo_canvas_export.png" ]; then
  chown ga:ga /home/ga/Desktop/osw_undo_canvas_export.png
  echo "✅ Exported canvas saved to Desktop."
else
  echo "⚠️ Export output missing; continuing to close GIMP."
fi

# Quit GIMP to persist preferences
su - ga -c "DISPLAY=:1 xdotool key ctrl+q" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1

echo "✅ GIMP closed; preferences saved."
