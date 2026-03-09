#!/bin/bash
set -e
echo "=== Setting up Merge Duplicate Records Task ==="

source /workspace/scripts/task_utils.sh

# timestamp
date +%s > /tmp/task_start_time.txt

# Wait for EHR to be ready
wait_for_librehealth 120

echo "Preparing duplicate data..."

# 1. Select a real NHANES patient to duplicate (offset 20 to avoid collisions with other tasks)
# We pick a patient, rename them to Cameron Fry for the scenario
ORIG_PID=$(librehealth_query "SELECT pid FROM patient_data LIMIT 1 OFFSET 20")

if [ -z "$ORIG_PID" ]; then
    echo "ERROR: Could not find a patient to duplicate."
    exit 1
fi

echo "Selected Master PID: $ORIG_PID"

# 2. Rename original to Cameron Fry
librehealth_query "UPDATE patient_data SET fname='Cameron', lname='Fry', mname='Alan' WHERE pid=$ORIG_PID"

# 3. Create the Duplicate (Clone the row)
# Use temporary table strategy to clone and let auto_increment assign new PID
librehealth_query "CREATE TEMPORARY TABLE tmp_patient SELECT * FROM patient_data WHERE pid=$ORIG_PID"
librehealth_query "UPDATE tmp_patient SET pid=NULL"
librehealth_query "INSERT INTO patient_data SELECT * FROM tmp_patient"
librehealth_query "DROP TEMPORARY TABLE tmp_patient"

# 4. Get the new PID (The one we just inserted will have the highest PID for this name)
NEW_PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='Cameron' AND lname='Fry' AND pid != $ORIG_PID ORDER BY pid DESC LIMIT 1")

if [ -z "$NEW_PID" ]; then
    echo "ERROR: Failed to create duplicate record."
    exit 1
fi

echo "Created Duplicate PID: $NEW_PID"

# 5. Save configuration for the agent and export script
cat > /tmp/merge_info.txt << EOF
TASK INFORMATION: MERGE DUPLICATES
----------------------------------
Patient Name: Cameron Fry
Original Record (KEEP THIS): PID $ORIG_PID
Duplicate Record (MERGE THIS): PID $NEW_PID

Instructions:
Merge PID $NEW_PID -> into -> PID $ORIG_PID
PID $ORIG_PID must remain.
EOF

# Save JSON for export_result.sh to read
cat > /tmp/merge_config.json << EOF
{
    "master_pid": $ORIG_PID,
    "duplicate_pid": $NEW_PID
}
EOF

# 6. Ensure Firefox is fresh and at login
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Master: $ORIG_PID | Duplicate: $NEW_PID"