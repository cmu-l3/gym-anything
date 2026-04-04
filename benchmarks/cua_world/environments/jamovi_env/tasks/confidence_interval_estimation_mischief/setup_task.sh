#!/bin/bash
set -e
echo "=== Setting up Confidence Interval Estimation Task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists in the user's Documents
# The environment setup renames "Invisibility Cloak.csv" to "InvisibilityCloak.csv"
DATA_SOURCE="/opt/jamovi_datasets/Invisibility Cloak.csv"
DATA_DEST="/home/ga/Documents/Jamovi/InvisibilityCloak.csv"

mkdir -p /home/ga/Documents/Jamovi

if [ -f "$DATA_SOURCE" ]; then
    cp "$DATA_SOURCE" "$DATA_DEST"
else
    # Fallback if the space-free version exists
    if [ -f "/opt/jamovi_datasets/InvisibilityCloak.csv" ]; then
        cp "/opt/jamovi_datasets/InvisibilityCloak.csv" "$DATA_DEST"
    else
        echo "ERROR: Dataset not found in /opt/jamovi_datasets"
        # Try to download it if missing (recovery)
        wget -q -O "$DATA_DEST" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/2.%20T-Tests/Invisibility%20Cloak.csv"
    fi
fi

# Ensure permissions
chown -R ga:ga /home/ga/Documents/Jamovi
chmod 644 "$DATA_DEST"

echo "Dataset prepared at $DATA_DEST"

# 3. Clean up previous artifacts
rm -f "/home/ga/Documents/Jamovi/Mischief_Estimation.omv"
rm -f "/home/ga/Documents/Jamovi/ci_report.txt"

# 4. Launch Jamovi (Blank State)
# We do NOT pass the file argument because the task requires the agent to open it.
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize and focus
# Jamovi window title is usually "jamovi" when empty, or the filename
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Dismiss any welcome dialogs/popups
# Sometimes a "What's New" or "Welcome" dialog appears
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="