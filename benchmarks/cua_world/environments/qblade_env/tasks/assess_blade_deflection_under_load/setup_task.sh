#!/bin/bash
set -e
echo "=== Setting up assess_blade_deflection_under_load task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/deflection_report.txt
rm -f /tmp/task_result.json
rm -f /tmp/task_final.png

# 3. Ensure sample projects are available
# (The environment install script puts them in /home/ga/Documents/sample_projects/)
mkdir -p /home/ga/Documents/sample_projects
if [ -z "$(ls -A /home/ga/Documents/sample_projects)" ]; then
    echo "WARNING: Sample projects dir empty, trying to copy from install..."
    SAMPLE_SRC=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
    if [ -n "$SAMPLE_SRC" ]; then
        cp "$SAMPLE_SRC"/* /home/ga/Documents/sample_projects/ 2>/dev/null || true
    fi
fi

# 4. Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# 5. Wait for window
wait_for_qblade 30

# 6. Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="