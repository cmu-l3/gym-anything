#!/bin/bash
set -e
echo "=== Setting up Food Crumb Porosity Analysis Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Fiji_Data/raw/food_science
mkdir -p /home/ga/Fiji_Data/results/food_science

# Clean previous results
rm -f /home/ga/Fiji_Data/results/food_science/*

# Download sample data (Real Sourdough Image)
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/2/23/Sourdough_bread_crumb.jpg"
OUTPUT_FILE="/home/ga/Fiji_Data/raw/food_science/sourdough_slice.jpg"

echo "Downloading sample data..."
if [ ! -f "$OUTPUT_FILE" ]; then
    wget -q --timeout=30 "$IMAGE_URL" -O "$OUTPUT_FILE" || {
        echo "Primary download failed, trying backup..."
        # Backup: Alternative bread texture
        wget -q "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c7/Korb%C3%A4ste.jpg/800px-Korb%C3%A4ste.jpg" -O "$OUTPUT_FILE"
    }
fi

# Ensure file ownership
chown -R ga:ga /home/ga/Fiji_Data

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
FIJI_PID=$!

# Wait for Fiji window
echo "Waiting for Fiji to start..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="