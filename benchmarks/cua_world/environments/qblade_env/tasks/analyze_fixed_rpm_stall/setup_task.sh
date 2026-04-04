#!/bin/bash
set -e
echo "=== Setting up analyze_fixed_rpm_stall task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
rm -f /home/ga/Documents/projects/stall_simulation_data.txt
rm -f /home/ga/Documents/projects/stall_report.txt
rm -f /home/ga/Documents/projects/stall_analysis.wpa
rm -f /tmp/task_result.json
rm -f /tmp/task_initial.png
rm -f /tmp/task_final.png

# 2. Ensure sample project exists
SAMPLE_PROJECT="/home/ga/Documents/sample_projects/NREL_5MW_Reference.wpa"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "Searching for NREL 5MW sample..."
    # Try to find it in QBlade install dir if not in user docs
    FOUND_SAMPLE=$(find /opt/qblade -name "*NREL*5MW*.wpa" 2>/dev/null | head -1)
    if [ -n "$FOUND_SAMPLE" ]; then
        cp "$FOUND_SAMPLE" "$SAMPLE_PROJECT"
        chown ga:ga "$SAMPLE_PROJECT"
        echo "Restored sample project from $FOUND_SAMPLE"
    else
        echo "WARNING: NREL 5MW sample project not found. Task may fail."
    fi
fi

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch QBlade
echo "Launching QBlade..."
launch_qblade

# 5. Wait for window and maximize
if wait_for_qblade 30; then
    sleep 2
    # Find window ID
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "qblade" | cut -d' ' -f1 | head -1)
    if [ -n "$WID" ]; then
        echo "Maximizing QBlade window ($WID)..."
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -i -a "$WID"
    fi
fi

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="