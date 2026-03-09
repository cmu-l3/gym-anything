#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Horizontal Mirror ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl

cd /home/ga/Desktop/

if [ ! -f berry.png ]; then
  echo "📥 Downloading berry image..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/72f83cdc-bf76-4531-9a1b-eb893a13f8aa/berry.jpeg" -O berry.png
fi

chown ga:ga berry.png
chmod 644 berry.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/berry.png > /tmp/gimp_osw_mirror.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Use Image → Transform → Flip Horizontally (or equivalent) to mirror the image." 
echo "   2. Ensure the result is a horizontal mirror." 
echo "   3. The export script will save the mirrored image."
