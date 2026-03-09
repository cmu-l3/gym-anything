#!/bin/bash
set -e
echo "=== Setting up Print Visitor Badge Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean previous artifacts
rm -f /home/ga/Documents/visitor_badge_output.pdf
rm -f /home/ga/Documents/visitor_badge_preview.png
mkdir -p /home/ga/Documents

# 3. Create Visitor Info File (Fallback if DB is empty)
cat > /home/ga/Desktop/Visitor_Info.txt <<EOF
Visitor Details for Registration (if record missing):
---------------------------------------------------
First Name: Margaret
Last Name: Chen
Company: Nextera Consulting
Host: David Park
Reason: Executive Meeting
EOF
chown ga:ga /home/ga/Desktop/Visitor_Info.txt

# 4. Launch Lobby Track
# Uses the utility function which handles Wine/Display settings
launch_lobbytrack

# 5. Wait for window to stabilize
sleep 5

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="