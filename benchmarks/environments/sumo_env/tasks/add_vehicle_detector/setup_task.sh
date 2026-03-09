#!/bin/bash
echo "=== Setting up add_vehicle_detector task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing SUMO processes
kill_sumo
sleep 1

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"

# Restore original detector file (remove any previous additions)
cp /workspace/data/bologna_acosta/acosta_detectors.add.xml "${WORK_DIR}/acosta_detectors.add.xml"
chown ga:ga "${WORK_DIR}/acosta_detectors.add.xml"

# Remove any previous new detector output
rm -f "${WORK_DIR}/new_detector_output.xml" 2>/dev/null || true

# Launch netedit with the network and additional files
echo "Launching netedit with Bologna Acosta network and additionals..."
su - ga -c "DISPLAY=:1 SUMO_HOME=/usr/share/sumo netedit -s ${WORK_DIR}/acosta_buslanes.net.xml -a ${WORK_DIR}/acosta_detectors.add.xml > /tmp/netedit.log 2>&1 &"

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
echo "Task: Add an E1 induction loop detector named 'new_detector_1' to the network."
