#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Export Rename ==="

apt-get update -qq
apt-get install -y -qq wget xdotool wmctrl

cd /home/ga/Desktop/

if [ ! -f The_Lost_River_Of_Dreams.jpg ]; then
  echo "📥 Downloading source photo..."
  wget -q "https://huggingface.co/datasets/xlangai/ubuntu_osworld_file_cache/resolve/main/gimp/77b8ab4d-994f-43ac-8930-8ca087d7c4b4/The_Lost_River_Of_Dreams.jpg" -O The_Lost_River_Of_Dreams.jpg
fi

chown ga:ga The_Lost_River_Of_Dreams.jpg
chmod 644 The_Lost_River_Of_Dreams.jpg

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/The_Lost_River_Of_Dreams.jpg > /tmp/gimp_osw_export.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Ensure the photo is ready for export."
echo "   2. Export it to the Desktop named export.jpg."
echo "   3. The export script will verify the saved file."
}
