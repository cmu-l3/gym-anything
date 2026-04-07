#!/bin/bash
set -e
echo "=== Setting up task: create_new_project_from_scratch ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Remove any existing output files to ensure clean state
rm -f /home/ga/Projects/solar_installation.xml
rm -f /home/ga/Projects/solar_installation.pod
rm -f /tmp/task_result.json

# Ensure Projects directory exists
mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

# Kill any existing ProjectLibre instances
pkill -f projectlibre 2>/dev/null || true
sleep 2
pkill -9 -f projectlibre 2>/dev/null || true
sleep 1

# Launch ProjectLibre fresh with no file (empty state)
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre > /tmp/projectlibre.log 2>&1 &"

# Wait for ProjectLibre window to appear
echo "Waiting for ProjectLibre window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre\|gantt\|project"; then
        echo "ProjectLibre window appeared after ${i}s"
        break
    fi
    sleep 1
done

# Extra wait for UI to fully render
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (tips, welcome, etc.)
# ProjectLibre often shows a "Welcome" or "Tip of the Day" dialog
for attempt in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Focus the main window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || \
DISPLAY=:1 wmctrl -a "Gantt" 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="