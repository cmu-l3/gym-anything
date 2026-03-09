#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Remove Background ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy

cd /home/ga/Desktop/

if [ ! -f dog_with_background.png ]; then
  echo "📥 Downloading dog image..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/2a729ded-3296-423d-aec4-7dd55ed5fbb3/dog_with_background.png" -O dog_with_background.png
fi
if [ ! -f dog_cutout_gold.png ]; then
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/2a729ded-3296-423d-aec4-7dd55ed5fbb3/dog_cutout_gold.png" -O dog_cutout_gold.png
fi

chown ga:ga dog_with_background.png dog_cutout_gold.png
chmod 644 dog_with_background.png dog_cutout_gold.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/dog_with_background.png > /tmp/gimp_osw_remove.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Use selection/masking tools to remove the background around the dog."
echo "   2. Aim to match the provided gold cutout reference."
echo "   3. The export script will save the result."
