#!/bin/bash
set -e
echo "=== Setting up Leaf Vein Skeleton Analysis Task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
TASK_START=$(cat /tmp/task_start_time.txt)
echo "Task start timestamp: $TASK_START"

# 2. Create directory structure
DATA_DIR="/home/ga/Fiji_Data/raw/leaf"
RESULTS_DIR="/home/ga/Fiji_Data/results/skeleton"

# Use su - ga to ensure permissions are correct from the start
su - ga -c "mkdir -p '$DATA_DIR'"
su - ga -c "mkdir -p '$RESULTS_DIR'"

# 3. Clean previous results
rm -f "$RESULTS_DIR"/* 2>/dev/null || true

# 4. Prepare Input Data
# Download leaf image from ImageJ samples (using curl/wget)
echo "Downloading leaf sample image..."
LEAF_URL="https://imagej.net/images/leaf.jpg"
LEAF_JPG="$DATA_DIR/leaf_original.jpg"
LEAF_TIF="$DATA_DIR/leaf_grayscale.tif"

if [ ! -f "$LEAF_JPG" ]; then
    wget -q --timeout=60 "$LEAF_URL" -O "$LEAF_JPG" || {
        echo "Primary download failed, trying mirror..."
        wget -q --timeout=60 "https://imagej.nih.gov/ij/images/leaf.jpg" -O "$LEAF_JPG" || {
             echo "ERROR: Failed to download leaf image."
             exit 1
        }
    }
fi

# Convert to 8-bit grayscale TIFF (Fiji skeletonize works best on 8-bit)
# Using python/PIL since imagemagick might be flaky in some envs, 
# but imagemagick is standard in the env spec. Let's use convert.
echo "Converting to grayscale TIFF..."
convert "$LEAF_JPG" -colorspace Gray -depth 8 "$LEAF_TIF"
chown ga:ga "$DATA_DIR"/*

# Create scale info file for agent reference
cat > "$DATA_DIR/scale_info.txt" << 'EOF'
Image: leaf_grayscale.tif
Pixel size: 5.0 um/pixel
Unit: um
Objective: 2x
Source: Cleared leaf section, transmitted light
EOF
chown ga:ga "$DATA_DIR/scale_info.txt"

# 5. Launch Fiji
echo "Launching Fiji..."
# Check if Fiji is already running to avoid duplicates
if pgrep -f "fiji\|ImageJ" > /dev/null; then
    echo "Fiji already running."
else
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    sleep 10
fi

# 6. Window Management
echo "Waiting for Fiji window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "fiji" 2>/dev/null || true

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Input: $LEAF_TIF"
echo "Output Directory: $RESULTS_DIR"