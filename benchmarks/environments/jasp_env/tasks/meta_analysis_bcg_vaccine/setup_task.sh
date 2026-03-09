#!/bin/bash
set -e
echo "=== Setting up task: Meta-Analysis BCG ==="

# 1. Setup paths and permissions
DATA_DIR="/home/ga/Documents/JASP"
DATA_FILE="$DATA_DIR/BCG Vaccine.csv"
mkdir -p "$DATA_DIR"
chown -R ga:ga "$DATA_DIR"

# 2. Download the specific Meta-Analysis dataset (not in standard install)
# URL from JASP GitHub Data Library
DATA_URL="https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/13.%20Meta-Analysis/BCG%20Vaccine.csv"

echo "Downloading BCG Vaccine dataset..."
if wget -q -O "$DATA_FILE" "$DATA_URL"; then
    echo "Download successful."
else
    echo "ERROR: Failed to download dataset."
    exit 1
fi

chown ga:ga "$DATA_FILE"
chmod 644 "$DATA_FILE"

# 3. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 4. Kill any existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# 5. Launch JASP with the dataset pre-loaded
echo "Launching JASP with data..."
# launch-jasp is the wrapper created in environment setup that handles flatpak/sandbox
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATA_FILE\" > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP to load..."
FOUND_WINDOW=0
for i in {1..50}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window found."
        FOUND_WINDOW=1
        break
    fi
    sleep 1
done

if [ $FOUND_WINDOW -eq 0 ]; then
    echo "WARNING: JASP window not found within timeout."
fi

# Allow UI to render
sleep 5

# 7. Maximize window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 8. Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="