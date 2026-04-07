#!/bin/bash
echo "=== Setting up update_arrest_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure OpenCAD is running
# (Already handled by env hooks, but good to double check via utility)

# 2. Clean up any previous attempts (Delete arrest records for Elena Fisher to ensure clean state)
# We want to start with exactly one 'Petty Theft' arrest
opencad_db_query "DELETE FROM ncic_arrests WHERE name_id IN (SELECT id FROM ncic_names WHERE name='Elena Fisher')"

# 3. Ensure Civilian 'Elena Fisher' exists
# Check if she exists
CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Elena Fisher' LIMIT 1")

if [ -z "$CIV_ID" ]; then
    echo "Creating civilian Elena Fisher..."
    opencad_db_query "INSERT INTO ncic_names (submittedByName, submittedById, name, dob, address, gender, race, dl_status, hair_color, build, weapon_permit, deceased) VALUES ('Admin User', '1A-01', 'Elena Fisher', '1985-10-14', '4248 Magellan Ave', 'Female', 'Caucasian', 'Valid', 'Blonde', 'Average', 'Unobtained', 'NO')"
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Elena Fisher' LIMIT 1")
fi

echo "Target Civilian ID: $CIV_ID"

# 4. Create the target Arrest Record
# Note: Using ncic_arrests table with proper column names.
# We explicitly set the arrest_reason to 'Petty Theft'.
NARRATIVE="Suspect apprehended at jewelry store attempting to conceal earrings. Suspect was cooperative."

echo "Creating initial arrest record..."
opencad_db_query "INSERT INTO ncic_arrests (name_id, arrest_reason, arrest_fine, issued_date, issued_by, narrative) VALUES ('$CIV_ID', 'Petty Theft', '250.00', DATE_FORMAT(NOW(), '%Y-%m-%d'), 'Admin User 1A-01', '$NARRATIVE')"

# Get the ID of the record we just created to track it
REPORT_ID=$(opencad_db_query "SELECT id FROM ncic_arrests WHERE name_id='$CIV_ID' AND arrest_reason='Petty Theft' ORDER BY id DESC LIMIT 1")
echo "$REPORT_ID" > /tmp/target_report_id.txt
echo "Created Arrest Report ID: $REPORT_ID"

# 5. Record start state
date +%s > /tmp/task_start_time.txt
