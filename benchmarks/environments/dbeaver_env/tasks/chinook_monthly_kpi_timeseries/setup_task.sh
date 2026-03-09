#!/bin/bash
echo "=== Setting up Chinook Monthly KPI Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/scripts
chown -R ga:ga /home/ga/Documents

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            echo "DBeaver window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any previous run artifacts
rm -f /home/ga/Documents/exports/monthly_kpi.csv
rm -f /home/ga/Documents/scripts/monthly_kpi.sql

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="