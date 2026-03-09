#!/bin/bash
set -e
echo "=== Setting up Bain Viagra Hypothesis Task ==="

# Source utilities if available, otherwise define basics
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    function take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Data Exists
# The environment install script puts data in /home/ga/Documents/JASP/
# We make sure it's fresh
DATA_DIR="/home/ga/Documents/JASP"
mkdir -p "$DATA_DIR"
if [ -f "/opt/jasp_datasets/Viagra.csv" ]; then
    cp "/opt/jasp_datasets/Viagra.csv" "$DATA_DIR/Viagra.csv"
    chown ga:ga "$DATA_DIR/Viagra.csv"
else
    echo "WARNING: Source dataset not found in /opt/jasp_datasets"
fi

# 3. Clean up previous run artifacts
rm -f "$DATA_DIR/Viagra_Bain.jasp"
rm -f "$DATA_DIR/bain_results.txt"

# 4. Start JASP cleanly
echo "Starting JASP..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP (using system-wide launcher if available, or direct flatpak)
if [ -f "/usr/local/bin/launch-jasp" ]; then
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_std.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 flatpak run org.jaspstats.JASP > /tmp/jasp_std.log 2>&1 &"
fi

# 5. Wait for JASP window
echo "Waiting for JASP to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and Focus
# Use wmctrl to find window ID for JASP
WID=$(DISPLAY=:1 wmctrl -l | grep -i "JASP" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 7. Initial Screenshot
sleep 5 # Wait for UI to render
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="