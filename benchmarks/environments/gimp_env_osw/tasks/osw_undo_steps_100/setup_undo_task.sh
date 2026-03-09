#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Set Undo Steps to 100 ==="

apt-get update -qq
apt-get install -y -qq xdotool wmctrl imagemagick

cd /home/ga/Desktop/

# Create informative canvas to load in GIMP
convert -size 1024x768 gradient:"#ffffff-#e0e0e0" \
  -fill '#1e88e5' -draw "rectangle 80,90 460,250" \
  -fill '#43a047' -draw "rectangle 560,430 940,590" \
  -fill '#0d47a1' -pointsize 54 -gravity north -annotate +0+120 "Undo Levels" \
  -fill '#263238' -pointsize 36 -gravity center -annotate +0+40 "Set preference to 100" \
  -fill '#546e7a' -pointsize 28 -gravity south -annotate +0+140 "Edit → Preferences → System Resources" \
  osw_undo_canvas.png

chown ga:ga osw_undo_canvas.png
chmod 644 osw_undo_canvas.png

# Launch GIMP with the canvas loaded
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/osw_undo_canvas.png > /tmp/gimp_osw_undo.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. GIMP is open with the task canvas." 
echo "   2. Navigate to Edit → Preferences → System Resources." 
echo "   3. Set Undo Steps to 100 and confirm." 
echo "   4. Continue when finished so the export script can capture evidence."
