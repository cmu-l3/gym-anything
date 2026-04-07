#!/bin/bash
echo "=== Setting up HL7 ADT to CSV Export Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Prepare output directory
OUTPUT_DIR="/home/ga/output"
mkdir -p "$OUTPUT_DIR"
# Ensure it's empty
rm -f "$OUTPUT_DIR/patient_demographics.csv"
# Ensure ga user owns it
chown -R ga:ga "$OUTPUT_DIR"
chmod 777 "$OUTPUT_DIR"

# Wait for NextGen Connect API
wait_for_api 60

# Open Terminal with instructions
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect Task: HL7 to CSV Export"
echo "============================================"
echo ""
echo "GOAL: Build a channel to convert HL7 ADT messages to CSV."
echo ""
echo "Specifications:"
echo " 1. Channel Name: ADT_CSV_Export"
echo " 2. Source: TCP Listener on Port 6661 (MLLP)"
echo " 3. Destination: File Writer to /home/ga/output/patient_demographics.csv"
echo " 4. Format: CSV with Header"
echo ""
echo "Required CSV Columns (PID segment):"
echo " PatientID,LastName,FirstName,DOB,Gender,Street,City,State,Zip,Phone,SSN"
echo ""
echo "API: https://localhost:8443/api (admin/admin)"
echo "Dashboard: https://localhost:8443"
echo ""
exec bash
' 2>/dev/null &

# Focus Terminal
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="