#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Hide Docks ==="

apt-get update -qq
apt-get install -y -qq xdotool wmctrl imagemagick

cd /home/ga/Desktop/

# Create workspace canvas for guidance
convert -size 1280x800 xc:'#263238' \
  -fill '#455a64' -draw "rectangle 160,100 1120,700" \
  -fill '#90a4ae' -pointsize 52 -gravity north -annotate +0+160 "Hide Docks Task" \
  -fill '#cfd8dc' -pointsize 32 -gravity center -annotate +0+0 "Use Shift+Tab or Windows → Hide Docks" \
  -fill '#b0bec5' -pointsize 28 -gravity south -annotate +0+180 "Goal: workspace with no dock panes visible" \
  osw_docks_canvas.png

chown ga:ga osw_docks_canvas.png
chmod 644 osw_docks_canvas.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/osw_docks_canvas.png > /tmp/gimp_osw_docks.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. GIMP is open with the docks canvas." 
echo "   2. Toggle Hide Docks (Shift+Tab) or use Windows → Hide Docks." 
echo "   3. Ensure all dock panes disappear." 
echo "   4. Continue so export can capture the state."
