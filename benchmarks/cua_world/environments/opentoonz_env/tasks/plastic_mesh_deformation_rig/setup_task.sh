#!/bin/bash
echo "=== Setting up plastic_mesh_deformation_rig task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure OpenToonz directories exist
su - ga -c "mkdir -p /home/ga/OpenToonz/output"

# Clean up any previous attempts
rm -f /home/ga/OpenToonz/output/slime_rig.tnz 2>/dev/null || true
rm -f /home/ga/OpenToonz/output/slime_idle.mp4 2>/dev/null || true
rm -f /home/ga/OpenToonz/output/*.tnz 2>/dev/null || true
rm -f /home/ga/OpenToonz/output/*.mp4 2>/dev/null || true

# Ensure OpenToonz is running and focused
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any potential startup dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="