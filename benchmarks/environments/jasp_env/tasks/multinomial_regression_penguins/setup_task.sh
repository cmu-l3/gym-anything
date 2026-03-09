#!/bin/bash
set -e
echo "=== Setting up Multinomial Regression task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Create JASP documents directory
mkdir -p /home/ga/Documents/JASP

# 3. Download Palmer Penguins dataset
# Using the raw CSV from the official GitHub repo
PENGUINS_URL="https://raw.githubusercontent.com/allisonhorst/palmerpenguins/master/inst/extdata/penguins.csv"
DEST_FILE="/home/ga/Documents/JASP/penguins.csv"

echo "Downloading penguins.csv..."
if [ ! -f "$DEST_FILE" ]; then
    wget -q -O "$DEST_FILE" "$PENGUINS_URL"
fi

# Verify download
if [ ! -f "$DEST_FILE" ]; then
    echo "ERROR: Failed to download penguins.csv"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$DEST_FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1000 ]; then
    echo "ERROR: penguins.csv too small ($FILE_SIZE bytes)"
    exit 1
fi
echo "penguins.csv ready ($FILE_SIZE bytes)"

# Set permissions
chown -R ga:ga /home/ga/Documents/JASP

# 4. Clean previous artifacts
rm -f /home/ga/Documents/JASP/Penguin_Multinomial.jasp
rm -f /home/ga/Documents/JASP/model_performance.txt

# 5. Launch JASP
# Use pgrep to check if already running
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    # Launch via su to run as user 'ga'
    # setsid ensures it runs in a new session
    su - ga -c "setsid /usr/local/bin/launch-jasp > /dev/null 2>&1 &"
    
    # Wait for window to appear
    echo "Waiting for JASP window..."
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window found."
            break
        fi
        sleep 1
    done
    sleep 5
else
    echo "JASP is already running."
fi

# 6. Maximize JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="