#!/bin/bash
set -e
echo "=== Setting up Lasso Regression Task ==="

# 1. Record Task Start Time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data
# Ensure the specific dataset exists with a space-free name for easier handling
SOURCE_DATA="/opt/jasp_datasets/Big Five Personality Traits.csv"
DEST_DIR="/home/ga/Documents/JASP"
DEST_FILE="$DEST_DIR/BigFivePersonalityTraits.csv"

mkdir -p "$DEST_DIR"
if [ -f "$SOURCE_DATA" ]; then
    echo "Copying dataset to $DEST_FILE..."
    cp "$SOURCE_DATA" "$DEST_FILE"
    chown ga:ga "$DEST_FILE"
else
    echo "ERROR: Source dataset not found at $SOURCE_DATA"
    # Fallback to verify if it was already copied during env setup
    if [ ! -f "$DEST_FILE" ]; then
        echo "CRITICAL: Dataset missing entirely."
        exit 1
    fi
fi

# 3. Clean previous run artifacts
rm -f "$DEST_DIR/LassoRegressionBigFive.jasp"
rm -f "$DEST_DIR/lasso_report.txt"

# 4. Launch JASP
# We use the custom launcher which handles the flatpak environment
echo "Launching JASP with dataset..."
pkill -f "org.jaspstats.JASP" || true
sleep 2

# Launch JASP via su to run as user 'ga'
# setsid ensures it runs in a new session and doesn't block
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DEST_FILE\" > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for JASP Window
echo "Waiting for JASP to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Configure Window (Maximize and Focus)
# Wait a bit for the UI to actually render
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss "Check for Updates" or Welcome dialogs if they appear
# Press Escape twice just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 8. Capture Initial State Evidence
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="