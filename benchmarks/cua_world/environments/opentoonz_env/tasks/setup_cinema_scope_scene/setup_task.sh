#!/bin/bash
set -e
echo "=== Setting up Cinema Scope Scene task ==="

# Define paths
PROJECT_DIR="/home/ga/OpenToonz/projects/cinema_short"
OUTPUT_DIR="/home/ga/OpenToonz/output/cinema_scope_test"

# 1. CLEAN STATE
# Remove the specific project directory if it exists to force creation
if [ -d "$PROJECT_DIR" ]; then
    echo "Removing existing project directory..."
    rm -rf "$PROJECT_DIR"
fi

# Ensure output directory exists but is empty (agent needs a place to put renders, 
# but often OpenToonz requires the directory to exist)
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning output directory..."
    rm -rf "$OUTPUT_DIR"
fi
# Recreate empty output directory
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. APP SETUP
# Ensure OpenToonz is running
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "opentoonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any startup dialogs (Esc/Enter)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 3. RECORD STATE
# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Target Project Path: $PROJECT_DIR/cinema_short.tnz"
echo "Target Output Path: $OUTPUT_DIR"