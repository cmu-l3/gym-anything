#!/bin/bash
echo "=== Setting up siu_to_adt_bridge task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy sample SIU S12 message
echo "Copying sample SIU S12 message..."
cp /workspace/assets/hl7-v2.5-siu-s12.hl7 /home/ga/sample_siu_s12.hl7
chown ga:ga /home/ga/sample_siu_s12.hl7
chmod 644 /home/ga/sample_siu_s12.hl7

# Also provide ADT A04 reference (pre-registration format)
cp /workspace/assets/hl7-v2.3-adt-a01-1.hl7 /home/ga/sample_adt_reference.hl7
chown ga:ga /home/ga/sample_adt_reference.hl7
chmod 644 /home/ga/sample_adt_reference.hl7

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_siubridge_channel_count 2>/dev/null || sudo rm -f /tmp/initial_siubridge_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_siubridge_channel_count 2>/dev/null || true

echo "Initial channel count: $INITIAL_COUNT"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=130x50+70+30 -- bash -c '
echo "========================================================"
echo " NextGen Connect - SIU to ADT Bridge Task"
echo "========================================================"
echo ""
echo "TASK: Build a 2-channel bridge converting SIU scheduling"
echo "      messages to ADT pre-registration events"
echo ""
echo "ARCHITECTURE:"
echo "  PMS -(SIU^S12)-> [SIU Intake Channel] -(Channel Writer)->"
echo "                   [ADT Pre-Registration Processor] -(DB Writer)->"
echo "                   scheduling_preregistrations table"
echo ""
echo "Sample message: /home/ga/sample_siu_s12.hl7"
echo "Reference ADT:  /home/ga/sample_adt_reference.hl7"
echo ""
echo "CHANNEL 1: SIU Intake Channel"
echo "  Port: TCP 6666 (MLLP)"
echo "  JS Transformer: Map SIU -> ADT fields"
echo "    - New MSH: message type ADT^A04"
echo "    - PID fields: MRN (PID-3.1), name (PID-5), DOB (PID-7), gender (PID-8)"
echo "    - Appointment datetime: SCH-11"
echo "    - Store as channelMap[transformedADT]"
echo "  Destination: Channel Writer -> ADT Pre-Registration Processor"
echo ""
echo "CHANNEL 2: ADT Pre-Registration Processor"
echo "  Source: Channel Reader (receives from Channel 1)"
echo "  Destination: Database Writer -> scheduling_preregistrations"
echo "    Columns: appt_id, patient_mrn, patient_name, appt_datetime, registered_at"
echo ""
echo "IMPORTANT: Deploy Channel 2 FIRST to get its channel ID,"
echo "           then create Channel 1 with Channel Writer referencing Channel 2"
echo ""
echo "Create table first:"
echo "  docker exec nextgen-postgres psql -U postgres -d mirthdb -c \\"
echo "  \"CREATE TABLE IF NOT EXISTS scheduling_preregistrations ("
echo "    appt_id VARCHAR(50), patient_mrn VARCHAR(50),"
echo "    patient_name VARCHAR(200), appt_datetime VARCHAR(50),"
echo "    registered_at TIMESTAMP DEFAULT NOW());\""
echo ""
echo "PostgreSQL (container): jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres  Password: postgres"
echo "REST API: https://localhost:8443/api | admin:admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo "========================================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="
