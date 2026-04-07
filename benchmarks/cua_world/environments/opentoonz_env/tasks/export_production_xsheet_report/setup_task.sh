#!/bin/bash
set -e
echo "=== Setting up export_production_xsheet_report task ==="

# Define paths
SCENE_SRC="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/outputs"
OUTPUT_FILE="$OUTPUT_DIR/xsheet_report.html"

# Ensure output directory exists
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean up previous outputs
rm -f "$OUTPUT_FILE" 2>/dev/null || true
echo "Cleaned previous output at $OUTPUT_FILE"

# Ensure sample data exists
if [ ! -f "$SCENE_SRC" ]; then
    echo "ERROR: Sample scene not found at $SCENE_SRC"
    # Try to copy from backup/installation if missing, or error out
    # For now, assume environment is set up correctly as per env definition
    exit 1
fi

# Reset scene to ensure clean state (if it was modified in previous run)
# We assume the samples directory might be writable, so we restore if a backup exists
# or just ensure we start fresh.
# (Optional: Reset logic here if needed)

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Launch OpenToonz if not running
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize and focus OpenToonz
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Close any open dialogs (escape key)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="