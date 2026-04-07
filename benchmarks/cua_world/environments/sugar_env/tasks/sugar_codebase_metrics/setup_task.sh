#!/bin/bash
echo "=== Setting up sugar_codebase_metrics task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous run
rm -f /home/ga/Documents/analyze_activities.sh 2>/dev/null || true
rm -f /home/ga/Documents/sugar_metrics.csv 2>/dev/null || true

# Generate Mystery.activity dynamically to prevent hardcoding
MYSTERY_DIR="/usr/share/sugar/activities/Mystery.activity"
rm -rf "$MYSTERY_DIR" 2>/dev/null || true
mkdir -p "$MYSTERY_DIR"

# Randomize python files (between 3 and 8)
NUM_FILES=$(( ( RANDOM % 6 ) + 3 ))

for i in $(seq 1 $NUM_FILES); do
    # Randomize lines of code (between 50 and 200)
    NUM_LINES=$(( ( RANDOM % 151 ) + 50 ))
    FILE_PATH="$MYSTERY_DIR/module_${i}.py"
    
    # Generate python code with correct number of newlines
    for l in $(seq 1 $NUM_LINES); do
        echo "print('This is line $l of module $i')" >> "$FILE_PATH"
    done
done

# Set permissions
chown -R root:root "$MYSTERY_DIR"
chmod -R 755 "$MYSTERY_DIR"

# Record task start timestamp
date +%s > /tmp/sugar_codebase_metrics_start_ts
chmod 666 /tmp/sugar_codebase_metrics_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-terminal-activity" &
sleep 8

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/sugar_metrics_task_start.png" 2>/dev/null || true

echo "=== sugar_codebase_metrics task setup complete ==="
echo "Mystery.activity created with $NUM_FILES files."
echo "Terminal is open. Agent must write analyze_activities.sh and generate sugar_metrics.csv"