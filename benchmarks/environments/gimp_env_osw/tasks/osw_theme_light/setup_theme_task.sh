#!/usr/bin/env bash
set -euo pipefail

echo "=== OSWorld Task Setup: Change Theme to Light ==="

apt-get update -qq
apt-get install -y -qq xdotool wmctrl imagemagick

cd /home/ga/Desktop/

# Create themed canvas for clarity
convert -size 1280x800 gradient:"#37474f-#eceff1" \
  -fill '#eceff1' -draw "rectangle 120,100 1160,700" \
  -fill '#263238' -pointsize 64 -gravity north -annotate +0+140 "Theme Configuration" \
  -fill '#546e7a' -pointsize 36 -gravity center -annotate +0+20 "Switch to Light Theme" \
  -fill '#78909c' -pointsize 28 -gravity south -annotate +0+180 "Edit → Preferences → Interface → Theme" \
  osw_theme_canvas.png

chown ga:ga osw_theme_canvas.png
chmod 644 osw_theme_canvas.png

su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/osw_theme_canvas.png > /tmp/gimp_osw_theme.log 2>&1 &"

sleep 5

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. GIMP is open with the theme canvas." 
echo "   2. Navigate to Edit → Preferences → Interface → Theme." 
echo "   3. Choose 'Light' and confirm." 
echo "   4. Proceed so the export script can capture state."
