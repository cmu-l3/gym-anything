#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Basic Presentation Result ==="

# Focus Impress window
focus_window "Impress" || focus_window "impress" || true
sleep 1

# Save file (Ctrl+S)
echo "Saving file..."
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 3

# Check for save dialog and handle it
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 2

# List what was saved
echo "Files in Presentations directory:"
ls -lh /home/ga/Documents/Presentations/ 2>/dev/null || true

# Close Impress
echo "Closing LibreOffice Impress..."
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+q" || true
sleep 2
# Dismiss any "save changes" dialog
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1

echo "=== Export Complete ==="
