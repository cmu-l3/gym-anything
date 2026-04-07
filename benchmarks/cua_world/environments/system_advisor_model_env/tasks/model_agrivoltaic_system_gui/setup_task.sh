#!/bin/bash
echo "=== Setting up model_agrivoltaic_system_gui task ==="

# Clean any pre-existing output files from previous runs
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects
rm -f /home/ga/Documents/SAM_Projects/agrivoltaic.sam 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time
chown ga:ga /home/ga/.task_start_time

# Wait for SAM application to be ready (started by env post_start hook)
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "System Advisor"; then
        echo "SAM application window detected"
        break
    fi
    sleep 1
done

# Maximize and focus the SAM window to ensure agent can see the UI
SAM_WID=$(DISPLAY=:1 wmctrl -l | grep -i "System Advisor" | awk '{print $1}' | head -1)
if [ -n "$SAM_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SAM_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SAM_WID" 2>/dev/null || true
fi

# Take initial screenshot showing starting state
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="