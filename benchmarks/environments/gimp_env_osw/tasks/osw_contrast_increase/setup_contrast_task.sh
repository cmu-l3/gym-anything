#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Increase Contrast ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl python3-pil python3-numpy

cd /home/ga/Desktop/

if [ ! -f berries.png ]; then
  echo "📥 Downloading berries image..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/f723c744-e62c-4ae6-98d1-750d3cd7d79d/file_1X42_kOanL74vu_p6QdcZuiyzDQi3kA7F.jpg" -O berries.png
fi

chown ga:ga berries.png
chmod 644 berries.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/berries.png > /tmp/gimp_osw_contrast.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Use Colors → Brightness-Contrast (or Levels/Curves) to increase contrast." 
echo "   2. Ensure subject stands out clearly." 
echo "   3. The export script will save the enhanced image."}
