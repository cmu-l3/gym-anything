#!/bin/bash
echo "=== Setting up HIPAA Notifications Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt

# Create a valid minimal WAV file for the custom sound
echo "UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=" | base64 -d > /home/ga/Documents/urgent_chime.wav
chown ga:ga /home/ga/Documents/urgent_chime.wav

# Find the active prefs.js to record its initial modification time
PREFS_FILE=$(find /home/ga/.thunderbird -name "prefs.js" | head -n 1)
if [ -n "$PREFS_FILE" ]; then
    stat -c %Y "$PREFS_FILE" > /tmp/initial_prefs_time.txt
else
    echo "0" > /tmp/initial_prefs_time.txt
fi

# Ensure Thunderbird is running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
    sleep 8
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Thunderbird"; then
        break
    fi
    sleep 1
done

# Focus and maximize the Thunderbird window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Thunderbird" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Click center of desktop to ensure interaction is ready
su - ga -c "DISPLAY=:1 xdotool mousemove 800 600 click 1" || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="