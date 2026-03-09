#!/bin/bash
echo "=== Setting up transform_hl7_format task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy sample HL7 ORU message to home directory
echo "Copying sample HL7 ORU message..."
cp /workspace/assets/hl7-v2.3-oru-r01-1.hl7 /home/ga/sample_oru_message.hl7
chown ga:ga /home/ga/sample_oru_message.hl7
chmod 644 /home/ga/sample_oru_message.hl7

# Also copy to /tmp
cp /workspace/assets/hl7-v2.3-oru-r01-1.hl7 /tmp/sample_oru_message.hl7
chmod 666 /tmp/sample_oru_message.hl7

# Record initial channel count for transformers
INITIAL_CHANNEL_COUNT=$(get_channel_count)
rm -f /tmp/initial_transformer_channel_count 2>/dev/null || sudo rm -f /tmp/initial_transformer_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_CHANNEL_COUNT" > /tmp/initial_transformer_channel_count 2>/dev/null || true

echo "Initial channel count: $INITIAL_CHANNEL_COUNT"
echo "Sample ORU message available at: /home/ga/sample_oru_message.hl7"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - HL7 Transformation"
echo "============================================"
echo ""
echo "TASK: Create a channel that transforms HL7 to XML"
echo ""
echo "Sample ORU message: /home/ga/sample_oru_message.hl7"
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
echo "  Check with: docker exec nextgen-connect ls /path/"
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
