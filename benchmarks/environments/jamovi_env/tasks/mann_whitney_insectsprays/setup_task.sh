#!/bin/bash
set -e
echo "=== Setting up Mann-Whitney U task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists
DATA_DIR="/home/ga/Documents/Jamovi"
mkdir -p "$DATA_DIR"
DATA_FILE="$DATA_DIR/InsectSprays.csv"

# The environment installation script puts it there, but we verify/restore it
if [ ! -f "$DATA_FILE" ]; then
    echo "Restoring InsectSprays.csv..."
    if [ -f "/opt/jamovi_datasets/InsectSprays.csv" ]; then
        cp "/opt/jamovi_datasets/InsectSprays.csv" "$DATA_FILE"
    else
        # Fallback download if missing (should not happen based on env spec)
        wget -q -O "$DATA_FILE" "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/datasets/InsectSprays.csv"
    fi
    chown ga:ga "$DATA_FILE"
fi

# 3. Clean up previous results
rm -f "$DATA_DIR/InsectSprays_MannWhitney.omv"
rm -f /tmp/task_result.json

# 4. Start Jamovi (Empty State)
# Kill any existing instances first
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

echo "Starting Jamovi..."
# Use the system-wide launcher wrapper created in the env setup
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# 5. Wait for Window
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi" > /dev/null; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# 6. Maximize Window
# Find the window ID to be specific
WID=$(DISPLAY=:1 wmctrl -l | grep -i "jamovi" | head -n 1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 7. Dismiss Welcome/Startup Dialogs (if any)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="