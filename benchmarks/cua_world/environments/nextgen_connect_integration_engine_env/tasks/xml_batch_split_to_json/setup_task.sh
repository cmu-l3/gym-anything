#!/bin/bash
set -e
echo "=== Setting up XML Batch Split to JSON Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
INBOX="/home/ga/Documents/inbox"
OUTBOX="/home/ga/Documents/outbox"
TASK_START_FILE="/tmp/task_start_time.txt"

# Record start time
date +%s > "$TASK_START_FILE"

# Create directories with proper permissions
mkdir -p "$INBOX" "$OUTBOX"
chmod 777 "$INBOX" "$OUTBOX"

# Clean any existing data to ensure a fresh start
rm -f "$INBOX"/*
rm -f "$OUTBOX"/*

# Create the batch XML file
cat > "$INBOX/daily_census.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Census>
  <Patient>
    <ID>1001</ID>
    <Name>Valerie Tinsley</Name>
    <DOB>1985-04-12</DOB>
    <Department>Cardiology</Department>
    <Room>304-A</Room>
  </Patient>
  <Patient>
    <ID>1002</ID>
    <Name>Robert Chen</Name>
    <DOB>1979-11-23</DOB>
    <Department>Oncology</Department>
    <Room>210-B</Room>
  </Patient>
  <Patient>
    <ID>1003</ID>
    <Name>Marcus Johnson</Name>
    <DOB>1992-02-15</DOB>
    <Department>Neurology</Department>
    <Room>405-A</Room>
  </Patient>
  <Patient>
    <ID>1004</ID>
    <Name>Sarah O'Connor</Name>
    <DOB>1955-08-30</DOB>
    <Department>Orthopedics</Department>
    <Room>102-C</Room>
  </Patient>
  <Patient>
    <ID>1005</ID>
    <Name>Elena Rodriguez</Name>
    <DOB>1988-06-18</DOB>
    <Department>Maternity</Department>
    <Room>501-A</Room>
  </Patient>
</Census>
EOF

# Set ownership to ensure the agent/Mirth can read it
chown -R ga:ga "/home/ga/Documents"
chmod 666 "$INBOX/daily_census.xml"

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Open a terminal for the agent
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "============================================"
echo " NextGen Connect - Batch Processing Task"
echo "============================================"
echo ""
echo "Input File: $HOME/Documents/inbox/daily_census.xml"
echo "Output Dir: $HOME/Documents/outbox/"
echo ""
echo "Goal: Split the XML into 5 separate JSON files."
echo ""
echo "REST API: https://localhost:8443/api"
echo "Web Dashboard: https://localhost:8443"
echo ""
echo "Use the File Reader batch settings!"
echo "============================================"
exec bash
' 2>/dev/null &

# Wait for terminal
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="