#!/bin/bash
echo "=== Setting up simulate_electric_bus_charging task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure SUMO processes are not running
kill_sumo
sleep 1

# Reset Pasubio scenario files to pristine condition
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUT_DIR="/home/ga/SUMO_Output"

# Restore original vtypes
cp /workspace/data/bologna_pasubio/pasubio_vtypes.add.xml "${WORK_DIR}/pasubio_vtypes.add.xml"
chown ga:ga "${WORK_DIR}/pasubio_vtypes.add.xml"

# Remove any previous agent-created files
rm -f "${WORK_DIR}/charging.add.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/ev_run.sumocfg" 2>/dev/null || true
rm -f "${OUT_DIR}/battery.xml" 2>/dev/null || true
rm -f "${OUT_DIR}/ev_report.txt" 2>/dev/null || true

# Ensure output directory exists and is clean
mkdir -p "${OUT_DIR}"
chown ga:ga "${OUT_DIR}"

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=${WORK_DIR} &"
    sleep 3
fi

# Focus and maximize the terminal
focus_and_maximize "Terminal"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="