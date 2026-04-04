#!/bin/bash
set -euo pipefail
echo "=== Setting up Tote Bag Pattern Task ==="

# 1. Kill any existing instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 2. Prepare workspace
# Ensure documents directory exists and is owned by ga
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove previous result file if it exists (crucial for anti-gaming)
rm -f /home/ga/Documents/LibreCAD/tote_bag_pattern.dxf

# 3. Record start state
# Timestamp for checking if file is new
date +%s > /tmp/task_start_time.txt

# 4. Start LibreCAD
echo "Starting LibreCAD..."
# Start with a new empty drawing
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 5. Configure Window
# Maximize to ensure all tools are visible for the agent
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="