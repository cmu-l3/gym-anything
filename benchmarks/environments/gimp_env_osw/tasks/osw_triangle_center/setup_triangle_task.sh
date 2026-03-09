#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Center Triangle ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy

cd /home/ga/Desktop/

if [ ! -f Triangle_On_The_Side.xcf ]; then
  echo "📥 Downloading triangle XCF..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/f4aec372-4fb0-4df5-a52b-79e0e2a5d6ce/Triangle_On_The_Side.xcf" -O Triangle_On_The_Side.xcf
fi
if [ ! -f Triangle_On_The_Side.png ]; then
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/f4aec372-4fb0-4df5-a52b-79e0e2a5d6ce/Triangle_On_The_Side.png" -O Triangle_On_The_Side.png
fi

chown ga:ga Triangle_On_The_Side.*
chmod 644 Triangle_On_The_Side.*

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/Triangle_On_The_Side.xcf > /tmp/gimp_osw_triangle.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Select the yellow triangle layer or object."
echo "   2. Move it to the center of the image."
echo "   3. Ensure it is approximately centered both horizontally and vertically."
