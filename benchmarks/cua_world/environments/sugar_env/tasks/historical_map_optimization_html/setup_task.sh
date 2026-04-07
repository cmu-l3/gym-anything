#!/bin/bash
echo "=== Setting up historical_map_optimization_html task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous runs
rm -f /home/ga/Documents/map_nw.jpg \
      /home/ga/Documents/map_ne.jpg \
      /home/ga/Documents/map_sw.jpg \
      /home/ga/Documents/map_se.jpg \
      /home/ga/Documents/map_viewer.html 2>/dev/null || true

# Download the historical map (Van Schagen 1689 World Map - Public Domain)
echo "Downloading source map..."
wget -q -O /home/ga/Documents/source_map.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/Van_Schagen_1689_World_Map.jpg/2560px-Van_Schagen_1689_World_Map.jpg"

# Fallback if download fails
if [ ! -s /home/ga/Documents/source_map.jpg ]; then
    echo "Download failed, creating synthetic fallback map..."
    # Create a 2560x1877 image with some text/pattern to simulate a map
    convert -size 2560x1877 gradient:blue-green -gravity center -pointsize 100 -annotate 0 "Historical Map" /home/ga/Documents/source_map.jpg
fi

chown ga:ga /home/ga/Documents/source_map.jpg

# Record original image dimensions
ORIG_DIMS=$(identify -format "%w %h" /home/ga/Documents/source_map.jpg 2>/dev/null || echo "2560 1877")
echo "$ORIG_DIMS" > /tmp/map_orig_dims.txt

# Record task start timestamp for mtime validation
date +%s > /tmp/map_task_start_ts
chmod 666 /tmp/map_task_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-terminal-activity" &
sleep 8

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/map_task_start.png" 2>/dev/null || true

echo "=== setup complete ==="
echo "Terminal is open. Map downloaded to /home/ga/Documents/source_map.jpg."