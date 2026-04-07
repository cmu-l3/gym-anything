#!/bin/bash
echo "=== Setting up Legacy Appointment Reconciliation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

echo "Setting up test data in DrTuxTest database..."

# 1. Clean up previous test data to ensure deterministic state
# Remove patients with our specific test names
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_NomFille IN ('TESTUNIQUE', 'TESTDUP', 'TESTMISSING');" 2>/dev/null || true
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_NomDos IN ('TESTUNIQUE', 'TESTDUP', 'TESTMISSING');" 2>/dev/null || true

# 2. Insert 'TESTUNIQUE Alice' (Unique Match)
GUID_ALICE="TEST_GUID_ALICE_001"
insert_patient "$GUID_ALICE" "TESTUNIQUE" "Alice" "1980-01-01" "F" "Mme" "1 Rue Unique" "75001" "Paris" "0101010101" "2800175001001"

# 3. Insert 'TESTDUP Bob' TWICE (Duplicate Match)
GUID_BOB1="TEST_GUID_BOB_001"
insert_patient "$GUID_BOB1" "TESTDUP" "Bob" "1990-01-01" "M" "M." "2 Rue Dup" "69002" "Lyon" "0202020202" "1900169002002"

GUID_BOB2="TEST_GUID_BOB_002"
insert_patient "$GUID_BOB2" "TESTDUP" "Bob" "1992-02-02" "M" "M." "3 Rue Dup" "69002" "Lyon" "0303030303" "1920269002003"

# 4. 'TESTMISSING Charlie' is intentionally NOT inserted.

echo "Database preparation complete."

# 5. Create the legacy CSV file
mkdir -p /home/ga/Documents
CSV_FILE="/home/ga/Documents/legacy_appointments.csv"

cat > "$CSV_FILE" << EOF
Date,Time,LastName,FirstName,Reason
25/12/2023,10:00,TESTUNIQUE,Alice,Routine Checkup
26/12/2023,11:00,TESTDUP,Bob,Knee Pain
27/12/2023,09:30,TESTMISSING,Charlie,New Patient Consultation
EOF

chown ga:ga "$CSV_FILE"
echo "Created $CSV_FILE"

# 6. Launch MedinTux (optional for this task, but strictly required by env standards)
# We launch it so the agent *can* use the UI if they choose to do it manually.
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="