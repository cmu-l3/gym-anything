#!/bin/bash
echo "=== Setting up develop_realtime_pick_monitor task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is running
ensure_scmaster_running

# Generate a dynamic pick ID to prevent hardcoding (anti-gaming mechanism)
RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 6 | head -n 1)
TARGET_PICK_ID="20240101.120000.00-AIC-GE.TOLI..BHZ-${RANDOM_SUFFIX}"
echo "$TARGET_PICK_ID" > /tmp/target_pick_id.txt
echo "Target Pick ID generated: $TARGET_PICK_ID"

# Create the sample SCML file
cat > /home/ga/sample_pick.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<seiscomp xmlns="http://geofon.gfz-potsdam.de/ns/seiscomp3-schema/0.11" version="0.11">
  <EventParameters>
    <pick publicID="$TARGET_PICK_ID">
      <time>
        <value>2024-01-01T12:00:00.0000Z</value>
      </time>
      <waveformID networkCode="GE" stationCode="TOLI" channelCode="BHZ"/>
      <filterID>BW(4,0.7,2)</filterID>
      <methodID>AIC</methodID>
      <phaseHint>P</phaseHint>
      <evaluationMode>manual</evaluationMode>
      <creationInfo>
        <agencyID>TEST</agencyID>
        <author>task_setup</author>
        <creationTime>2024-01-01T12:00:05.0000Z</creationTime>
      </creationInfo>
    </pick>
  </EventParameters>
</seiscomp>
EOF
chown ga:ga /home/ga/sample_pick.xml

# Ensure clean state (remove any previously created scripts or logs)
rm -f /home/ga/pick_monitor.py
rm -f /home/ga/pick_log.txt

# Wait for the desktop environment to settle before capturing initial state
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="