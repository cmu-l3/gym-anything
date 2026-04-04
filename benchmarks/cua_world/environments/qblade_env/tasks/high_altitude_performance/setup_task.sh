#!/bin/bash
set -e
echo "=== Setting up High Altitude Performance Task ==="

source /workspace/scripts/task_utils.sh

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/projects/altitude_study.wpa
rm -f /home/ga/Documents/projects/altitude_report.txt

# 3. Prepare directories
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents/projects

# 4. Find a suitable sample project
# QBlade usually ships with sample projects. We'll pick one to load.
SAMPLE_DIR="/home/ga/Documents/sample_projects"
SAMPLE_PROJECT=$(find "$SAMPLE_DIR" -name "*.wpa" | head -n 1)

if [ -z "$SAMPLE_PROJECT" ]; then
    echo "WARNING: No sample project found in $SAMPLE_DIR. Searching /opt/qblade..."
    SAMPLE_PROJECT=$(find /opt/qblade -name "*.wpa" | head -n 1)
fi

# 5. Launch QBlade with the sample project
echo "Launching QBlade with project: $SAMPLE_PROJECT"
if [ -n "$SAMPLE_PROJECT" ]; then
    launch_qblade "$SAMPLE_PROJECT"
else
    # Fallback: Launch empty if no sample found (Agent will have to generate one, making task harder but possible)
    launch_qblade
fi

# 6. Wait for QBlade window
wait_for_qblade 60

# 7. Maximize window
echo "Maximizing QBlade..."
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="