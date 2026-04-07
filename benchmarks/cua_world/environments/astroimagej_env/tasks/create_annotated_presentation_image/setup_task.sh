#!/bin/bash
echo "=== Setting up Create Annotated Presentation Image task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create required directories
su - ga -c "mkdir -p /home/ga/AstroImages/raw"
su - ga -c "mkdir -p /home/ga/AstroImages/processed"

# Ensure the source file exists in the correct location
SOURCE_FILE="/home/ga/AstroImages/raw/uit_galaxy_sample.fits"
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Copying sample file to user directory..."
    if [ -f "/opt/fits_samples/uit_galaxy_sample.fits" ]; then
        cp "/opt/fits_samples/uit_galaxy_sample.fits" "$SOURCE_FILE"
        chown ga:ga "$SOURCE_FILE"
    else
        echo "ERROR: Source sample file not found in /opt/fits_samples/"
        exit 1
    fi
fi

# Clean up any previous task artifacts
rm -f /home/ga/AstroImages/processed/uit_presentation.png
rm -f /tmp/task_result.json

# Start AstroImageJ if not running
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"
    
    # Wait for the window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ"; then
            echo "AstroImageJ window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize and focus the AstroImageJ window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take an initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="