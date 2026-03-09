#!/bin/bash
set -e
echo "=== Setting up blade_root_transition_design task ==="

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/projects/root_transition_geometry.dat
rm -f /home/ga/Documents/projects/blade_design_task.wpa
rm -f /tmp/task_result.json
rm -f /tmp/task_final.png

# 2. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents/projects

# 4. Start QBlade if not running
if ! pgrep -f "QBlade" > /dev/null; then
    echo "Starting QBlade..."
    # Launch via the standard launch script or directly
    su - ga -c "DISPLAY=:1 /home/ga/Desktop/launch_qblade.sh &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "QBlade"; then
            echo "QBlade window detected"
            break
        fi
        sleep 1
    done
fi

# 5. Maximize and focus
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="