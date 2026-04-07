#!/bin/bash
echo "=== Setting up csv_batch_to_hl7_transformation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create source CSV file with realistic data
cat > /home/ga/appointments.csv << 'EOF'
MRN,FirstName,LastName,DOB,Sex,VisitDate,ClinicCode
1001,John,Smith,1980-01-15,M,2025-10-20 09:00,CARDIO
1002,Jane,Doe,1992-05-22,F,2025-10-20 09:30,DERM
1003,Robert,Johnson,1975-11-30,M,2025-10-20 10:15,ORTHO
1004,Emily,Davis,2010-03-12,F,2025-10-20 11:00,PEDS
1005,Michael,Brown,1955-08-05,M,2025-10-20 13:45,CARDIO
EOF

chown ga:ga /home/ga/appointments.csv
chmod 644 /home/ga/appointments.csv

# Ensure directories exist inside the container
docker exec nextgen-connect mkdir -p /tmp/csv_input /tmp/hl7_output
docker exec nextgen-connect chown -R nextgen:nextgen /tmp/csv_input /tmp/hl7_output 2>/dev/null || true
# Note: User inside container might be different, ensuring writable
docker exec nextgen-connect chmod 777 /tmp/csv_input /tmp/hl7_output

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count

# Open a terminal with instructions
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Batch CSV to HL7"
echo "============================================"
echo ""
echo "TASK: Ingest CSV, split batches, transform to HL7."
echo ""
echo "Source File (Host): /home/ga/appointments.csv"
echo "Container Input:    /tmp/csv_input  (inside nextgen-connect)"
echo "Container Output:   /tmp/hl7_output (inside nextgen-connect)"
echo ""
echo "Steps:"
echo "1. Create channel reading from /tmp/csv_input"
echo "2. Configure Batch Processing & CSV Data Type"
echo "3. Map fields to HL7 (PID, PV1 segments)"
echo "4. Write to /tmp/hl7_output"
echo "5. Deploy channel"
echo "6. Copy file to trigger: docker cp /home/ga/appointments.csv nextgen-connect:/tmp/csv_input/"
echo ""
echo "REST API: https://localhost:8443/api"
echo "Creds: admin / admin"
echo ""
echo "Tools: docker, curl, python3"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Setup complete ==="