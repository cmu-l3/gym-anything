#!/bin/bash
echo "=== Setting up create_hl7_channel task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_channel_count 2>/dev/null || sudo rm -f /tmp/initial_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_channel_count 2>/dev/null || true
echo "Initial channel count: $INITIAL_COUNT"

# Ensure NextGen Connect is running
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200"; then
    echo "Warning: NextGen Connect may not be fully ready"
fi

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect Integration Engine"
echo " Channel Management Terminal"
echo "============================================"
echo ""
echo "NextGen Connect REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  IMPORTANT: All API calls require header: X-Requested-With: OpenAPI"
echo ""
echo "Web Dashboard (monitoring only): https://localhost:8443"
echo "Landing Page: http://localhost:8080"
echo ""
echo "Available HL7 ports: 6661, 6662, 6663"
echo "PostgreSQL: docker exec nextgen-postgres psql -U postgres -d mirthdb"
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
