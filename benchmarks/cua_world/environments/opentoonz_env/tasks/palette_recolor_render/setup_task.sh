#!/bin/bash
set -e
echo "=== Setting up palette_recolor_render task ==="

# Task parameters
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/recolor"

# 1. Prepare Output Directory
# Clean up any previous run artifacts
echo "Cleaning output directory: $OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify Source Data
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to copy from backup if available or fail
    if [ -f "/usr/share/opentoonz/samples/dwanko_run.tnz" ]; then
        cp "/usr/share/opentoonz/samples/dwanko_run.tnz" "$SOURCE_SCENE"
        chown ga:ga "$SOURCE_SCENE"
    else
        echo "Critical error: Sample data missing."
        exit 1
    fi
fi

# 3. Setup OpenToonz
# Close any running instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Launch OpenToonz
echo "Launching OpenToonz..."
# We launch without the file argument first to ensure clean UI, 
# then let the agent open it (part of the task is finding the file)
# OR we can open it for them. The description says "Open the scene file...", implying agent does it.
# However, to be nice and ensure consistent starting state, we'll launch the app.
su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"

# Wait for window
echo "Waiting for OpenToonz window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss popup dialogs if any (standard OpenToonz startup)
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 4. Record State
# Timestamp for anti-gaming (files must be newer than this)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="