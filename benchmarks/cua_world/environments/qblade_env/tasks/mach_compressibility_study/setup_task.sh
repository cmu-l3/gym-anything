#!/bin/bash
set -e
echo "=== Setting up Mach Compressibility Study ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
PROJECT_DIR="/home/ga/Documents/projects"
mkdir -p "$PROJECT_DIR"
rm -f "$PROJECT_DIR/mach_study.wpa" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 3. Ensure QBlade is running and ready
if ! is_qblade_running > /dev/null; then
    echo "Launching QBlade..."
    launch_qblade
    
    # Wait for window
    wait_for_qblade 30
fi

# 4. Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="