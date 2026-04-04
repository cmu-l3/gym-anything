#!/bin/bash
set -e
echo "=== Setting up Badge Design Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "design_badge_with_host_field"

# Ensure clean state for the proof screenshot
rm -f /home/ga/Desktop/badge_host_proof.png

# Create a "Work Order" file on the desktop with the specific names
# This ensures the agent has easy access to the exact spelling required
cat > /home/ga/Desktop/Badge_Update_Request.txt <<EOF
URGENT: UPDATE VISITOR BADGE TEMPLATE

Security requires the Host's Name to be visible on all visitor badges.

1. Edit the "Standard Visitor" badge template.
2. Add the Host's Full Name field.
3. Label it clearly with "Host:".

VERIFICATION STEPS:
1. Register this test visitor:
   - Name: Alice Verifier
   - Host: Bob Manager
2. Preview the badge.
3. Take a screenshot of the preview.
4. Save screenshot to: /home/ga/Desktop/badge_host_proof.png
EOF
chown ga:ga /home/ga/Desktop/Badge_Update_Request.txt

# Launch Lobby Track
ensure_lobbytrack_running

# Wait a moment for window to settle
sleep 5

# Take initial screenshot for reference
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="