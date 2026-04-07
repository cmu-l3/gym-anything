#!/bin/bash
echo "=== Setting up batch_astrophoto_enhancement task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Define paths
DOCS_DIR="/home/ga/Documents"
RAW_DIR="$DOCS_DIR/raw_astro"
ENHANCED_DIR="$DOCS_DIR/enhanced_astro"
SCRIPT_PATH="$DOCS_DIR/enhance_astrophotos.sh"

# Clean up any previous state
rm -rf "$RAW_DIR" "$ENHANCED_DIR" "$SCRIPT_PATH" 2>/dev/null || true
mkdir -p "$RAW_DIR"

# Download real astronomical images (Wikimedia Commons) and artificially underexpose them
echo "Downloading and preparing real astronomical data..."

# Image 1: NGC 4414 (Spiral Galaxy)
wget -q -O /tmp/img1.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c3/NGC_4414_%28NASA-med%29.jpg/1280px-NGC_4414_%28NASA-med%29.jpg"
# Image 2: Eagle Nebula Pillars
wget -q -O /tmp/img2.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b2/Eagle_nebula_pillars.jpg/1280px-Eagle_nebula_pillars.jpg"
# Image 3: Crab Nebula
wget -q -O /tmp/img3.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Crab_Nebula.jpg/1280px-Crab_Nebula.jpg"

# Apply extreme darkening and save to raw_astro directory
# If wget failed (no internet), generate procedural "star field" noise as a fallback
for i in 1 2 3; do
    if [ -s "/tmp/img${i}.jpg" ]; then
        # Real data: multiply pixel values by 0.15 to make it extremely underexposed
        convert "/tmp/img${i}.jpg" -evaluate multiply 0.15 "$RAW_DIR/astro_${i}.jpg"
    else
        # Fallback fake data (only if network is unavailable)
        echo "Warning: Download failed, using generated fallback data for astro_${i}.jpg"
        convert -size 1200x900 xc:black +noise Gaussian -evaluate multiply 0.1 "$RAW_DIR/astro_${i}.jpg"
    fi
done
rm -f /tmp/img*.jpg

# Set permissions so agent user 'ga' can access and modify
chown -R ga:ga "$DOCS_DIR"

# Close any open Sugar activities to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-terminal-activity" &
sleep 5

# Ensure window is maximized
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="
echo "3 raw astrophotos are ready in $RAW_DIR"