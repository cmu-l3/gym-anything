#!/bin/bash
echo "=== Setting up design_detailed_pv_cec_hardware task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/detailed_hardware_design.sam 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/design_summary.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure the SAM GUI is running
if ! pgrep -f "sam" > /dev/null && ! pgrep -f "SAM" > /dev/null; then
    echo "Starting SAM..."
    if [ -f "/usr/local/bin/sam" ]; then
        su - ga -c "DISPLAY=:1 /usr/local/bin/sam &"
        sleep 10
    fi
fi

# Maximize and focus the SAM window if it exists
for i in {1..10}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "system advisor" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        echo "SAM window maximized and focused."
        break
    fi
    sleep 1
done

# Ensure a terminal is available for the agent (for saving the JSON file)
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take an initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="