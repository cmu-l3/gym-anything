#!/bin/bash
echo "=== Setting up patient_index_deduplication task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy sample ADT A31 message (demographic update)
echo "Copying sample ADT A31 message..."
cp /workspace/assets/hl7-v2.5-adt-a31.hl7 /home/ga/sample_adt_a31.hl7
chown ga:ga /home/ga/sample_adt_a31.hl7
chmod 644 /home/ga/sample_adt_a31.hl7

# Also provide ADT A01 for testing
cp /workspace/assets/hl7-v2.3-adt-a01-1.hl7 /home/ga/sample_adt_a01.hl7
chown ga:ga /home/ga/sample_adt_a01.hl7
chmod 644 /home/ga/sample_adt_a01.hl7

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_pmisync_channel_count 2>/dev/null || sudo rm -f /tmp/initial_pmisync_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_pmisync_channel_count 2>/dev/null || true

echo "Initial channel count: $INITIAL_COUNT"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=130x45+70+30 -- bash -c '
echo "========================================================"
echo " NextGen Connect - Patient Master Index Sync Task"
echo "========================================================"
echo ""
echo "TASK: Build a deduplication channel for patient demographics"
echo "      using PostgreSQL ON CONFLICT (upsert) logic"
echo ""
echo "Sample messages:"
echo "  ADT A31 (demographic update): /home/ga/sample_adt_a31.hl7"
echo "  ADT A01 (admission):          /home/ga/sample_adt_a01.hl7"
echo ""
echo "Channel requirements:"
echo "  Name: Patient Master Index Sync"
echo "  Port: TCP 6665 (MLLP)"
echo "  JS Transformer: Extract PID fields -> channel map variables"
echo "    - mrn (PID-3.1), last_name (PID-5.1), first_name (PID-5.2)"
echo "    - dob (PID-7), gender (PID-8), ssn (PID-19)"
echo "  DB Writer: INSERT ... ON CONFLICT (mrn) DO UPDATE SET ..."
echo "    Table: patient_master_index"
echo "    Columns: mrn (PK), last_name, first_name, dob, gender, ssn,"
echo "             last_updated, update_count"
echo "  Response Transformer: Build HL7 ACK using MSH-10 (control ID)"
echo "  Channel: Must be deployed"
echo ""
echo "Create the table first if needed:"
echo "  docker exec nextgen-postgres psql -U postgres -d mirthdb -c \\"
echo "    \"CREATE TABLE IF NOT EXISTS patient_master_index ("
echo "       mrn VARCHAR(50) PRIMARY KEY,"
echo "       last_name VARCHAR(100),"
echo "       first_name VARCHAR(100),"
echo "       dob VARCHAR(20),"
echo "       gender VARCHAR(5),"
echo "       ssn VARCHAR(20),"
echo "       last_updated TIMESTAMP DEFAULT NOW(),"
echo "       update_count INTEGER DEFAULT 1"
echo "     );\""
echo ""
echo "PostgreSQL (from container): jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  Username: postgres  Password: postgres"
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo "========================================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="
