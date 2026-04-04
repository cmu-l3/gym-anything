#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Benchmark Encryption Task ==="

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/benchmark_report.txt 2>/dev/null || true
mkdir -p /home/ga/Documents

# 2. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure VeraCrypt is running and visible
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Wait for window and focus
if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure it's not minimized
    DISPLAY=:1 wmctrl -i -r "$wid" -b remove,hidden,shaded 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null || true
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="