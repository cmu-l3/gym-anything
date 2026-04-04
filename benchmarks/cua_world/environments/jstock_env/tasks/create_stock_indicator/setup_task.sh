#!/bin/bash
echo "=== Setting up Create Stock Indicator Task ==="

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ============================================================
# Clean up previous custom indicators
# ============================================================
# JStock stores indicators in ~/.jstock/<version>/indicator/ or similar
# We'll remove files containing "HighMomentum" to ensure a clean start
find /home/ga/.jstock -type f -name "*HighMomentum*" -delete 2>/dev/null || true
find /home/ga/.jstock -type f -exec grep -l "HighMomentum" {} + | xargs rm -f 2>/dev/null || true

# Record initial file count in .jstock to detect additions
find /home/ga/.jstock -type f | wc -l > /tmp/initial_file_count.txt

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
# Use the launcher script created in env setup
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start
echo "Waiting for JStock window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "jstock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done
sleep 5

# Dismiss JStock News dialog (Enter usually works)
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 1
# Fallback Escape
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="