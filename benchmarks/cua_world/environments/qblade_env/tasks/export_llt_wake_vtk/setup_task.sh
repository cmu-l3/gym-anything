#!/bin/bash
set -e
echo "=== Setting up export_llt_wake_vtk task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. cleanup previous runs
rm -f /home/ga/Documents/projects/wake_cutplane.* 2>/dev/null || true
rm -f /home/ga/Documents/projects/llt_simulation.wpa 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 3. Ensure sample projects are available
# (The environment setup copies them, but we ensure permissions here)
if [ -d "/home/ga/Documents/sample_projects" ]; then
    chown -R ga:ga /home/ga/Documents/sample_projects
else
    mkdir -p /home/ga/Documents/sample_projects
    # Try to find samples in install dir if missing
    SAMPLE_SRC=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
    if [ -n "$SAMPLE_SRC" ]; then
        cp "$SAMPLE_SRC"/* /home/ga/Documents/sample_projects/ 2>/dev/null || true
    fi
fi

# 4. Launch QBlade
echo "Launching QBlade..."
launch_qblade

# 5. Wait for window
wait_for_qblade 30

# 6. Maximize window (Crucial for VLM)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="