#!/bin/bash
set -e
echo "=== Setting up cinema_2k_tiff_alpha_render task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/cinema_2k_tiff"

# 1. Prepare Output Directory (Clean State)
# Create directory if it doesn't exist, clear it if it does
su - ga -c "mkdir -p $OUTPUT_DIR"
# Remove any existing files to ensure we verify new work
find "$OUTPUT_DIR" -type f -delete 2>/dev/null || true
echo "Output directory prepared: $OUTPUT_DIR"

# 2. Verify Data Availability
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to download/restore if missing (fallback)
    # For now, we assume environment setup was correct, but we'll flag it
    exit 1
fi
echo "Source scene verified."

# 3. Anti-Gaming Timestamp
# Record the exact time the task starts. Any result files must be modified AFTER this.
date +%s > /tmp/task_start_timestamp.txt
echo "Task start timestamp recorded: $(cat /tmp/task_start_timestamp.txt)"

# 4. Launch Application
# Ensure OpenToonz is running and focused
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize the window for visibility
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 5. Capture Initial State
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="