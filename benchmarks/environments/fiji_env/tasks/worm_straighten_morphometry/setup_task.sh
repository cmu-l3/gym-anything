#!/bin/bash
set -e
echo "=== Setting up Worm Straightening Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create required directories
su - ga -c "mkdir -p /home/ga/Fiji_Data/raw/bbbc010"
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/straighten"

# Clean any previous results
rm -f /home/ga/Fiji_Data/results/straighten/* 2>/dev/null || true

# Download BBBC010 dataset (C. elegans)
DATA_DIR="/home/ga/Fiji_Data/raw/bbbc010"
echo "Checking for dataset in $DATA_DIR..."

if [ -z "$(ls -A $DATA_DIR 2>/dev/null)" ]; then
    echo "Downloading BBBC010 images..."
    cd /tmp
    # Try primary source
    wget -q --timeout=180 "https://data.broadinstitute.org/bbbc/BBBC010/BBBC010_v1_images.zip" -O bbbc010.zip 2>/dev/null || \
    wget -q --timeout=180 "https://data.broadinstitute.org/bbbc/BBBC010/BBBC010_v2_images.zip" -O bbbc010.zip 2>/dev/null

    if [ -s bbbc010.zip ]; then
        unzip -q -o bbbc010.zip -d "$DATA_DIR/"
        rm bbbc010.zip
        
        # Flatten directory if nested
        find "$DATA_DIR" -mindepth 2 -type f -exec mv -t "$DATA_DIR" {} + 2>/dev/null || true
        find "$DATA_DIR" -type d -empty -delete 2>/dev/null || true
        
        echo "Dataset downloaded."
    else
        echo "ERROR: Failed to download dataset. Creating placeholder for testing (NOT FOR PRODUCTION)."
        # In production, this should fail. For robustness, we ensure directory exists.
    fi
fi

# Ensure correct permissions
chown -R ga:ga /home/ga/Fiji_Data

# Create info file for the agent
cat > "$DATA_DIR/scale_info.txt" << 'EOF'
Dataset: BBBC010 C. elegans
Pixel Size: 2.087 microns/pixel
Channels: w1 (GFP/Live), w2 (PI/Dead)
EOF
chown ga:ga "$DATA_DIR/scale_info.txt"

# Launch Fiji if not running
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    echo "Launching Fiji..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
    sleep 10
fi

# Wait for Fiji window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "Fiji|ImageJ"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize Fiji
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="