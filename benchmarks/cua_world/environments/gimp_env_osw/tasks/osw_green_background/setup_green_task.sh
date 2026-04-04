#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Fill Background with Green ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy

cd /home/ga/Desktop/

if [ ! -f white_background_with_object.xcf ]; then
  echo "📥 Downloading XCF project..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/734d6579-c07d-47a8-9ae2-13339795476b/white_background_with_object.xcf" -O white_background_with_object.xcf
fi
if [ ! -f white_background_with_object.png ]; then
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/734d6579-c07d-47a8-9ae2-13339795476b/white_background_with_object.png" -O white_background_with_object.png
fi

chown ga:ga white_background_with_object.xcf white_background_with_object.png
chmod 644 white_background_with_object.xcf white_background_with_object.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/white_background_with_object.xcf > /tmp/gimp_osw_green.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Select the background layer."
echo "   2. Fill it with a green color while keeping the object unchanged."
echo "   3. The export script will save the edited PNG."
