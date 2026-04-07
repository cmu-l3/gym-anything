#!/bin/bash
echo "=== Setting up configure_actuated_tsp task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"
mkdir -p "$OUTPUT_DIR"

# Clean up any previous runs
kill_sumo
sleep 1
rm -f "$WORK_DIR/tripinfos.xml" 2>/dev/null || true
rm -f "$WORK_DIR/sumo_log.txt" 2>/dev/null || true
rm -f "$OUTPUT_DIR/bus_travel_times.txt" 2>/dev/null || true

# Ensure pristine baseline for the TLS file and backup
cp /workspace/data/bologna_pasubio/pasubio_tls.add.xml "$WORK_DIR/pasubio_tls.add.xml"
cp "$WORK_DIR/pasubio_tls.add.xml" "$WORK_DIR/pasubio_tls.add.xml.bak"
chown ga:ga "$WORK_DIR/pasubio_tls.add.xml" "$WORK_DIR/pasubio_tls.add.xml.bak"

# Start netedit to establish visual context of the network
echo "Launching netedit with Bologna Pasubio network..."
su - ga -c "DISPLAY=:1 SUMO_HOME=/usr/share/sumo netedit -s $WORK_DIR/pasubio_buslanes.net.xml -a $WORK_DIR/pasubio_tls.add.xml > /tmp/netedit.log 2>&1 &"

# Wait for netedit window to appear
sleep 3
wait_for_window "netedit\|NETEDIT" 30
sleep 3

# Maximize netedit
focus_and_maximize "netedit\|NETEDIT"
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="