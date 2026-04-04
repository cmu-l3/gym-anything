#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Resize Dog Layer to 512px ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy

cd /home/ga/Desktop/

if [ ! -f dog_with_background_two_layers.xcf ]; then
  echo "📥 Downloading two-layer XCF..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/d16c99dc-2a1e-46f2-b350-d97c86c85c15/dog_with_background_two_layers.xcf" -O dog_with_background_two_layers.xcf
fi
if [ ! -f dog_with_background.png ]; then
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/d16c99dc-2a1e-46f2-b350-d97c86c85c15/dog_with_background.png" -O dog_with_background.png
fi

chown ga:ga dog_with_background_two_layers.xcf dog_with_background.png
chmod 644 dog_with_background_two_layers.xcf dog_with_background.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/dog_with_background_two_layers.xcf > /tmp/gimp_osw_resize.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Select the dog layer."
echo "   2. Resize it so the height becomes 512 pixels, keeping aspect ratio."
echo "   3. Export script will save the resized result."
