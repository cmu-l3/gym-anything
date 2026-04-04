#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Open Vignette Filter ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl

cd /home/ga/Desktop/

if [ ! -f dog_with_background.png ]; then
  echo "📥 Downloading dog_with_background.png..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/a746add2-cab0-4740-ac36-c3769d9bfb46/dog_with_background.png" -O dog_with_background.png
fi

chown ga:ga dog_with_background.png
chmod 644 dog_with_background.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/dog_with_background.png > /tmp/gimp_osw_vignette.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. With the image open, navigate to Filters → Light and Shadow → Vignette."
echo "   2. Ensure the Vignette dialog appears."
echo "   3. The export script will capture evidence and close the app."
