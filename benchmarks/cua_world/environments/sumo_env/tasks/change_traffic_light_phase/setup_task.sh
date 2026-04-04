#!/bin/bash
echo "=== Setting up change_traffic_light_phase task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Create a working copy of the network file so edits don't affect the original
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
BACKUP_NET="${WORK_DIR}/acosta_buslanes.net.xml.bak"

# Backup original network file if not already backed up
if [ ! -f "$BACKUP_NET" ]; then
    cp "${WORK_DIR}/acosta_buslanes.net.xml" "$BACKUP_NET"
    chown ga:ga "$BACKUP_NET"
fi

# Restore from backup to ensure clean state
cp "$BACKUP_NET" "${WORK_DIR}/acosta_buslanes.net.xml"
chown ga:ga "${WORK_DIR}/acosta_buslanes.net.xml"

# Record initial state of traffic light definitions
cp "${WORK_DIR}/acosta_buslanes.net.xml" /tmp/initial_network.xml

# Launch netedit with the network file
echo "Launching netedit with Bologna Acosta network..."
su - ga -c "DISPLAY=:1 SUMO_HOME=/usr/share/sumo netedit ${WORK_DIR}/acosta_buslanes.net.xml > /tmp/netedit.log 2>&1 &"

# Wait for netedit window to appear
sleep 3
wait_for_window "netedit\|NETEDIT" 30

# Give time to fully load
sleep 3

# Focus and maximize
focus_and_maximize "netedit\|NETEDIT"
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Edit traffic light phase duration to 45 seconds in netedit."
