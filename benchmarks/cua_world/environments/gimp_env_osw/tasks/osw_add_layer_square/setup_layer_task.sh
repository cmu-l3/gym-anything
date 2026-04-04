#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Add Layer Named Square ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl

cd /home/ga/Desktop/

# Download base XCF if not already present
if [ ! -f white_background.xcf ]; then
  echo "📥 Downloading white background XCF..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/b148e375-fe0b-4bec-90e7-38632b0d73c2/white_background.xcf" -O white_background.xcf
fi

chown ga:ga white_background.xcf
chmod 644 white_background.xcf

echo "🎨 Opening GIMP with white_background.xcf..."
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/white_background.xcf > /tmp/gimp_osw_layer.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Use Layer → New Layer (Ctrl+Shift+N) to add a layer."
echo "   2. Name the new layer 'Square'."
echo "   3. Confirm and ensure the layer exists."
echo "   4. The export script will handle saving evidence."
