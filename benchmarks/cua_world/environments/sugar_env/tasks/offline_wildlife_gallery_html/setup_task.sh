#!/bin/bash
echo "=== Setting up offline_wildlife_gallery_html task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Clean any existing directories from previous attempts
rm -rf /home/ga/Documents/wildlife_gallery 2>/dev/null || true
rm -rf /home/ga/Documents/wildlife_photos 2>/dev/null || true

# Prepare the photos directory
mkdir -p /home/ga/Documents/wildlife_photos
chown ga:ga /home/ga/Documents/wildlife_photos

echo "Downloading real wildlife images..."
IMG1="https://upload.wikimedia.org/wikipedia/commons/8/87/Monarch_butterfly_on_swamp_milkweed.jpg"
IMG2="https://upload.wikimedia.org/wikipedia/commons/b/be/Red_eyed_tree_frog_edit2.jpg"
IMG3="https://upload.wikimedia.org/wikipedia/commons/1/18/Galapagos_Tortoise.jpg"

# Download with timeout; fallback to ImageMagick fractal generation if offline/failed
wget -q -T 10 -O /home/ga/Documents/wildlife_photos/monarch_butterfly.jpg "$IMG1" || \
  su - ga -c "convert -size 1920x1080 plasma:fractal /home/ga/Documents/wildlife_photos/monarch_butterfly.jpg"
  
wget -q -T 10 -O /home/ga/Documents/wildlife_photos/red_eyed_tree_frog.jpg "$IMG2" || \
  su - ga -c "convert -size 1920x1080 plasma:fractal /home/ga/Documents/wildlife_photos/red_eyed_tree_frog.jpg"
  
wget -q -T 10 -O /home/ga/Documents/wildlife_photos/galapagos_tortoise.jpg "$IMG3" || \
  su - ga -c "convert -size 1920x1080 plasma:fractal /home/ga/Documents/wildlife_photos/galapagos_tortoise.jpg"

# Ensure all files are owned by the agent user
chown -R ga:ga /home/ga/Documents/wildlife_photos

# Close any open Sugar activities to return to the home view cleanly
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Take an initial screenshot verifying the task state
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="