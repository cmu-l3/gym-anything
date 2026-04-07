#!/bin/bash
echo "=== Setting up generate_snr_report_scamp task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is running and DB is accessible
ensure_scmaster_running

# Clean up any pre-existing files that might interfere or give false credit
rm -f /home/ga/snr_report.csv 2>/dev/null || true
rm -f /home/ga/picks.xml /home/ga/amps.xml 2>/dev/null || true

# Record initial database counts in case the agent routes output to the DB
INITIAL_PICK_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Pick" 2>/dev/null || echo "0")
INITIAL_AMP_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Amplitude" 2>/dev/null || echo "0")

echo "$INITIAL_PICK_COUNT" > /tmp/initial_pick_count.txt
echo "$INITIAL_AMP_COUNT" > /tmp/initial_amp_count.txt

# Ensure terminal is open and focused for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Capture initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="