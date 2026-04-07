#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Animations Result ==="

focus_window "Impress" || focus_window "animation_test" || true
sleep 1

# Save file
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 3

# Handle any save dialog
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 2

echo "Files in Presentations directory:"
ls -lh /home/ga/Documents/Presentations/ 2>/dev/null || true

# Close Impress
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+q" || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1

echo "=== Export Complete ==="
