#!/bin/bash
echo "=== Setting up lab_critical_value_router task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy sample HL7 ORU messages (critical and normal)
echo "Copying sample HL7 ORU messages..."
cp /workspace/assets/hl7-v2.5-oru-critical-r01.hl7 /home/ga/sample_critical_oru.hl7
chown ga:ga /home/ga/sample_critical_oru.hl7
chmod 644 /home/ga/sample_critical_oru.hl7

cp /workspace/assets/hl7-v2.5-oru-normal-r01.hl7 /home/ga/sample_normal_oru.hl7
chown ga:ga /home/ga/sample_normal_oru.hl7
chmod 644 /home/ga/sample_normal_oru.hl7

# Also provide the existing ORU messages for reference
cp /workspace/assets/hl7-v2.3-oru-r01-1.hl7 /home/ga/sample_oru_v23.hl7 2>/dev/null || true

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_critrouter_channel_count 2>/dev/null || sudo rm -f /tmp/initial_critrouter_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_critrouter_channel_count 2>/dev/null || true

echo "Initial channel count: $INITIAL_COUNT"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=130x40+70+30 -- bash -c '
echo "========================================================"
echo " NextGen Connect - Lab Critical Value Router Task"
echo "========================================================"
echo ""
echo "TASK: Build a 3-destination HL7 channel that routes lab"
echo "      results by severity (critical vs normal)"
echo ""
echo "Sample messages:"
echo "  Critical ORU (OBX-8=HH): /home/ga/sample_critical_oru.hl7"
echo "  Normal ORU  (OBX-8=N):   /home/ga/sample_normal_oru.hl7"
echo ""
echo "Channel requirements:"
echo "  Name: Lab Critical Value Router"
echo "  Port: TCP 6664 (MLLP)"
echo "  Transformer: JavaScript checking OBX-8 for HH/LL"
echo "  Destination 1: DB Writer -> critical_lab_results (filter: isCritical=true)"
echo "  Destination 2: DB Writer -> normal_lab_results (filter: isCritical=false)"
echo "  Destination 3: File Writer -> /tmp/lab_audit/ (no filter)"
echo ""
echo "PostgreSQL (from container): jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  Username: postgres  Password: postgres"
echo "  Direct access: docker exec nextgen-postgres psql -U postgres -d mirthdb"
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo "  Web Dashboard (monitoring): https://localhost:8443"
echo ""
echo "Tools: curl, nc (netcat), docker, python3"
echo "========================================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="
