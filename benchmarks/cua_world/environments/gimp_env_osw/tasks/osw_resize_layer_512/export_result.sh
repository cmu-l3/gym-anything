#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Export: Resize Layer to 512px ==="

apt-get update -qq && apt-get install -y -qq xdotool wmctrl || true

wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
  su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
  sleep 1
fi

su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+e" || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool type osw_resized_layer" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 2

if [ -f "/home/ga/Desktop/osw_resized_layer.png" ]; then
  chown ga:ga /home/ga/Desktop/osw_resized_layer.png
  echo "✅ Exported resized image saved to Desktop."
else
  echo "⚠️ Export output missing."
fi

su - ga -c "DISPLAY=:1 xdotool key ctrl+q" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1

echo "✅ GIMP closed."
