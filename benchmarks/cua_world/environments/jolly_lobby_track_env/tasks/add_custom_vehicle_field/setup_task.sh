#!/bin/bash
set -e
echo "=== Setting up add_custom_vehicle_field task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
record_start_time "add_custom_vehicle_field"

# Remove any previous screenshot
rm -f /home/ga/Desktop/vehicle_field_verification.png

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait a moment for UI to stabilize
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Create a "work order" file on desktop for context (adds realism)
cat > /home/ga/Desktop/IT_Ticket_1042.txt << EOF
TICKET #1042: Configure Visitor Vehicle Tracking
PRIORITY: High
REQUESTER: Facilities Security

DESCRIPTION:
Security requires us to log license plates for all visitors starting today.
Please configure the Lobby Track software to include a field for "Vehicle License Plate".
Verify it works by entering a test record.

TEST DATA:
Visitor: Carlos Mendez (Pacific Fleet Services)
Plate: 7XKP392
Host: Sarah Chen
EOF
chmod 666 /home/ga/Desktop/IT_Ticket_1042.txt

echo "=== Task setup complete ==="