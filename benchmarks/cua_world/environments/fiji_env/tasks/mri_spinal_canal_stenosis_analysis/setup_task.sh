#!/bin/bash
echo "=== Setting up Spinal Canal Stenosis Analysis Task ==="

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time
TASK_START=$(cat /tmp/task_start_time)
echo "Task start timestamp: $TASK_START"

# Create output directories with correct permissions
echo "Creating output directories..."
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/stenosis"

# Clean up any previous results to ensure we measure new work
echo "Cleaning previous results..."
rm -f /home/ga/Fiji_Data/results/stenosis/canal_measurements.csv 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/stenosis/diagnosis.txt 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/stenosis/segmentation_evidence.png 2>/dev/null || true
rm -f /tmp/stenosis_result.json 2>/dev/null || true

# Launch Fiji
echo "Launching Fiji..."
# Check if Fiji is already running, if not launch it
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    # Wait for Fiji to initialize
    sleep 10
else
    echo "Fiji is already running."
fi

# Ensure window is maximized for the agent
echo "Maximizing Fiji window..."
timeout=30
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        DISPLAY=:1 wmctrl -r "fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
        DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Window maximized."
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Target directory: /home/ga/Fiji_Data/results/stenosis/"