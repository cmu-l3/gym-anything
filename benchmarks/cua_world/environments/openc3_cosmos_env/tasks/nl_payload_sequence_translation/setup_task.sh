#!/bin/bash
echo "=== Setting up Natural Language Translation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/observation_sequence.py 2>/dev/null || true
rm -f /tmp/nl_translation_result.json 2>/dev/null || true
rm -f /home/ga/Documents/POR-INST-2026-084.txt 2>/dev/null || true

# Create the POR document
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/POR-INST-2026-084.txt << 'EOF'
=================================================================
                PAYLOAD OPERATIONS REQUEST (POR)
=================================================================
POR ID:       POR-INST-2026-084
TARGET:       INST
AUTHOR:       Dr. E. Vance, Principal Investigator
DATE:         March 9, 2026
=================================================================

OPERATIONAL SEQUENCE:
Please create an automated ground script for the following actions:

1. Send a command to start data collection with parameters set
   to TYPE: NORMAL and DURATION: 5.
2. Pause the sequence for exactly 5.0 seconds to allow the
   filter wheel to lock into position.
3. Send a command to start data collection with parameters set
   to TYPE: HIGH_RES and DURATION: 10.
4. Send a command to clear the instrument state to acknowledge
   any limit flags triggered by the high-current draw.

NOTES:
- Script must run autonomously without human input.
- Write the script to /home/ga/Desktop/observation_sequence.py
=================================================================
EOF
chown ga:ga /home/ga/Documents/POR-INST-2026-084.txt

# Record task start timestamp AFTER cleanup
date +%s > /tmp/nl_translation_start_ts
echo "Task start recorded: $(cat /tmp/nl_translation_start_ts)"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Open the POR file in gedit for the agent to easily read
su - ga -c "DISPLAY=:1 gedit /home/ga/Documents/POR-INST-2026-084.txt &"
sleep 3

# Take initial screenshot
take_screenshot /tmp/nl_translation_start.png

echo "=== Natural Language Translation Setup Complete ==="
echo ""
echo "Task: Translate the POR into an automated Python script."
echo "Output must be written to: /home/ga/Desktop/observation_sequence.py"
echo ""