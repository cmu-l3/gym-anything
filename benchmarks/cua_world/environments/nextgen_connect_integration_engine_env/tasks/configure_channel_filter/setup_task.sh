#!/bin/bash
echo "=== Setting up configure_channel_filter task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy both sample HL7 messages for testing the filter
echo "Copying sample HL7 messages..."
cp /workspace/assets/hl7-v2.3-adt-a01-1.hl7 /home/ga/sample_adt_message.hl7
cp /workspace/assets/hl7-v2.3-oru-r01-1.hl7 /home/ga/sample_oru_message.hl7
chown ga:ga /home/ga/sample_adt_message.hl7 /home/ga/sample_oru_message.hl7
chmod 644 /home/ga/sample_adt_message.hl7 /home/ga/sample_oru_message.hl7

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_filter_channel_count 2>/dev/null || sudo rm -f /tmp/initial_filter_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_filter_channel_count 2>/dev/null || true

echo "Initial channel count: $INITIAL_COUNT"
echo "ADT message available at: /home/ga/sample_adt_message.hl7"
echo "ORU message available at: /home/ga/sample_oru_message.hl7"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Channel Filtering"
echo "============================================"
echo ""
echo "TASK: Create a channel that filters by message type"
echo ""
echo "Test messages:"
echo "  ADT (should pass): /home/ga/sample_adt_message.hl7"
echo "  ORU (should be filtered): /home/ga/sample_oru_message.hl7"
echo ""
echo "Available port: 6662"
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo ""
echo "Web Dashboard (monitoring): https://localhost:8443"
echo "PostgreSQL: docker exec nextgen-postgres psql -U postgres -d mirthdb"
echo ""
echo "NOTE: Output files from File Writer destinations go INSIDE"
echo "  the Docker container, not the host filesystem."
echo ""
echo "Tools: curl, nc (netcat), docker, python3"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="
