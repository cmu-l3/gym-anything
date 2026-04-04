#!/bin/bash
set -e
echo "=== Setting up garden_bed_layout task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any previous output to ensure clean state
rm -f /home/ga/Documents/LibreCAD/garden_layout.dxf
rm -f /tmp/dxf_analysis.json
rm -f /tmp/task_result.json

# Ensure workspace exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Kill any existing LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a blank drawing (no arguments)
# Using su - ga to run as the correct user
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"
sleep 6

# Dismiss any startup dialogs (First Run Wizard often appears on fresh installs)
# Hitting Escape/Enter a few times helps clear modal dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 0.5

# Wait for LibreCAD window to be visible
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== garden_bed_layout task setup complete ==="