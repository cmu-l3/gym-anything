#!/bin/bash
set -e

echo "=== OSWorld: Setup undo steps to 100 task ==="
# Ensure basic tools
apt-get update -qq || true
apt-get install -y -qq xdotool wmctrl || true

# Launch GIMP (session already has GIMP installed and VNC running)
su - ga -c "DISPLAY=:1 gimp > /tmp/gimp_osw.log 2>&1 &"

sleep 3
echo "✅ GIMP launched. Proceed to Preferences → System Resources → set Undo steps to 100 and confirm."
