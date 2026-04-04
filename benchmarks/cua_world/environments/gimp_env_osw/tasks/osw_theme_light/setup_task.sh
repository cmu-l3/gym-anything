#!/bin/bash
set -e

echo "=== OSWorld: Setup change theme to Light ==="
apt-get update -qq || true
apt-get install -y -qq xdotool wmctrl || true

su - ga -c "DISPLAY=:1 gimp > /tmp/gimp_osw.log 2>&1 &"

sleep 3
echo "✅ GIMP launched. Go to Edit → Preferences → Interface → Theme: Light, then OK."
