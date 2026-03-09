#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Increase Saturation ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy python3-scipy

cd /home/ga/Desktop/

if [ ! -f woman_sitting_by_the_tree2.png ]; then
  echo "📥 Downloading source photo..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/554785e9-4523-4e7a-b8e1-8016f565f56a/woman_sitting_by_the_tree2.png" -O woman_sitting_by_the_tree2.png
fi

chown ga:ga woman_sitting_by_the_tree2.png
chmod 644 woman_sitting_by_the_tree2.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/woman_sitting_by_the_tree2.png > /tmp/gimp_osw_saturation.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Use Colors → Hue-Saturation (or equivalent) to increase vibrancy."
echo "   2. Ensure saturation is meaningfully enhanced."
echo "   3. The export script will save the result."
