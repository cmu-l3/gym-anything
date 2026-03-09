#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Reduce Brightness ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy

cd /home/ga/Desktop/

# if [ ! -f woman_sitting_by_the_tree.png ]; then
  echo "📥 Downloading source photo..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/7a4deb26-d57d-4ea9-9a73-630f66a7b568/woman_sitting_by_the_tree.png" -O woman_sitting_by_the_tree.png
# fi

chown ga:ga woman_sitting_by_the_tree.png
chmod 644 woman_sitting_by_the_tree.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/woman_sitting_by_the_tree.png > /tmp/gimp_osw_brightness.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Use Colors → Brightness-Contrast (or equivalent) to darken the photo."
echo "   2. Ensure brightness is reduced while preserving structure."
echo "   3. The export script will save the edited image."
