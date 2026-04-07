#!/bin/bash
echo "=== Setting up HL7 Enrichment DB Lookup Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Database
echo "Setting up database table..."
wait_for_postgres || exit 1

# Create table and populate sample data
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
DROP TABLE IF EXISTS patient_contacts;
CREATE TABLE patient_contacts (
    mrn VARCHAR(50) PRIMARY KEY,
    email VARCHAR(100)
);
INSERT INTO patient_contacts (mrn, email) VALUES 
('PAT1001', 'pat1001@example.com'),
('PAT1002', 'pat1002@hospital.org'),
('PAT_TEST', 'initial_test@test.com');
"

# 2. Prepare Directories
mkdir -p /home/ga/enriched_output
chown -R ga:ga /home/ga/enriched_output
chmod 777 /home/ga/enriched_output

# 3. Record Initial State
get_channel_count > /tmp/initial_channel_count
date +%s > /tmp/task_start_time

# 4. Launch Helper Terminal
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " TASK: HL7 Enrichment via Database Lookup"
echo "======================================================="
echo "1. Create channel: HL7_Enricher"
echo "2. Source: TCP Listener on port 6661 (MLLP)"
echo "3. Logic: Query DB for email using PID-3.1 (MRN)"
echo "   - Table: patient_contacts"
echo "   - Columns: mrn, email"
echo "   - JDBC: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "   - Creds: postgres / postgres"
echo "4. Logic: Put email into PID-13.4"
echo "5. Destination: File Writer to /home/ga/enriched_output/"
echo ""
echo "Sample MRN to test: PAT1001 (Email: pat1001@example.com)"
echo "======================================================="
exec bash
' 2>/dev/null &

# 5. Ensure Window Focus
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="