#!/bin/bash
echo "=== Setting up optimize_tls_offset_sweep task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean of artifacts
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/optimize_offset.py
rm -f /home/ga/SUMO_Output/offset_results.csv
rm -f /home/ga/SUMO_Output/best_tls.add.xml
chown -R ga:ga /home/ga/SUMO_Output

# Ensure scenario files are clean
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/tripinfos.xml

# Backup the original TLS file so the user has a fresh start if they mess up
cp /home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_tls.add.xml /home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_tls.add.xml.bak
chown ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_tls.add.xml.bak

# Launch a terminal for the user to work in
echo "Launching terminal..."
if command -v gnome-terminal &> /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
else
    su - ga -c "DISPLAY=:1 x-terminal-emulator &"
fi

# Wait a moment for terminal to appear
sleep 3

# Maximize the active window (terminal)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="