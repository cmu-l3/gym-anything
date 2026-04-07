#!/bin/bash
set -e
echo "=== Setting up greenscreen_bg_render task ==="

# 1. Prepare directories
OUTPUT_DIR="/home/ga/OpenToonz/output/greenscreen"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"
chown -R ga:ga /home/ga/OpenToonz/output

# 2. Verify sample file exists
SAMPLE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
if [ ! -f "$SAMPLE" ]; then
    echo "ERROR: Sample file not found at $SAMPLE"
    # Attempt to locate it if path is slightly different in this env version
    FOUND=$(find /home/ga -name "dwanko_run.tnz" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        SAMPLE="$FOUND"
        echo "Found sample at: $SAMPLE"
    else
        exit 1
    fi
fi

# 3. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Start OpenToonz
# We start it clean; agent must load the file.
if ! pgrep -f "opentoonz" > /dev/null 2>&1; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /tmp/opentoonz.log 2>&1 &"
    
    # Wait for window to appear
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "opentoonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    
    # Wait extra time for initialization
    sleep 10
fi

# 5. Handle Dialogs & Maximize
echo "Handling UI state..."
# Attempt to close common startup popups (Escape usually works)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize main window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Initial Evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Start time: $(cat /tmp/task_start_time.txt)"