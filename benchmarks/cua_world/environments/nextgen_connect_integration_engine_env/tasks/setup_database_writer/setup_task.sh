#!/bin/bash
echo "=== Setting up setup_database_writer task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy sample HL7 ADT message for testing
echo "Copying sample HL7 message..."
cp /workspace/assets/hl7-v2.3-adt-a01-1.hl7 /home/ga/sample_adt_message.hl7
chown ga:ga /home/ga/sample_adt_message.hl7
chmod 644 /home/ga/sample_adt_message.hl7

# Also provide the v2.4 message for additional testing
cp /workspace/assets/hl7-v2.4-oru-r01-1.hl7 /home/ga/sample_v24_message.hl7
chown ga:ga /home/ga/sample_v24_message.hl7
chmod 644 /home/ga/sample_v24_message.hl7

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_dbwriter_channel_count 2>/dev/null || sudo rm -f /tmp/initial_dbwriter_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_dbwriter_channel_count 2>/dev/null || true

# Check if patient_records table already exists
TABLE_EXISTS=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='patient_records';" 2>/dev/null || echo "0")
rm -f /tmp/initial_patient_table_exists 2>/dev/null || sudo rm -f /tmp/initial_patient_table_exists 2>/dev/null || true
printf '%s' "$TABLE_EXISTS" > /tmp/initial_patient_table_exists 2>/dev/null || true

echo "Initial channel count: $INITIAL_COUNT"
echo "Patient records table exists: $TABLE_EXISTS"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Database Writer Channel"
echo "============================================"
echo ""
echo "TASK: Create a channel that writes HL7 data to PostgreSQL"
echo ""
echo "Sample ADT message: /home/ga/sample_adt_message.hl7"
echo "Available port: 6663"
echo ""
echo "Database connection (from inside NextGen Connect container):"
echo "  JDBC URL: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  Username: postgres"
echo "  Password: postgres"
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo ""
echo "Web Dashboard (monitoring): https://localhost:8443"
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
