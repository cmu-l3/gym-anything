#!/bin/bash
set -e

echo "=== OSWorld: Setup hide docks ==="
apt-get update -qq || true
apt-get install -y -qq xdotool wmctrl || true

su - ga -c "DISPLAY=:1 gimp > /tmp/gimp_osw.log 2>&1 &"

sleep 3
echo "✅ GIMP launched. Toggle docks off via Windows → Hide Docks or relevant setting."
