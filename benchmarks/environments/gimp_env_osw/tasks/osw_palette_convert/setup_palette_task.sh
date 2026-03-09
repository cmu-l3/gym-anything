#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Convert to Palette-Based ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy

cd /home/ga/Desktop/

if [ ! -f computer.png ]; then
  echo "📥 Downloading computer image..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/06ca5602-62ca-47f6-ad4f-da151cde54cc/computer.png" -O computer.png
fi

chown ga:ga computer.png
chmod 644 computer.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/computer.png > /tmp/gimp_osw_palette.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Use Image → Mode → Indexed to convert to palette-based." 
echo "   2. Export as palette-based PNG." 
echo "   3. The export script will save the result."
