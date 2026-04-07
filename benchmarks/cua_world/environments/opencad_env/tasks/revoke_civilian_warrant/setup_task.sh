#!/bin/bash
echo "=== Setting up Revoke Civilian Warrant task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Marcus Vance exists in ncic_names
# We check if he exists, if not we create him.
echo "Checking for civilian Marcus Vance..."
CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Marcus Vance' LIMIT 1")

if [ -z "$CIV_ID" ]; then
    echo "Creating civilian Marcus Vance..."
    opencad_db_query "INSERT INTO ncic_names (submittedByName, submittedById, name, dob, address, gender, race, dl_status, hair_color, build, weapon_permit, deceased) VALUES ('Admin User', '1A-01', 'Marcus Vance', '1980-05-12', '852 Industrial Rd', 'Male', 'Caucasian', 'Valid', 'Brown', 'Average', 'Unobtained', 'NO')"
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Marcus Vance' LIMIT 1")
fi

echo "Target Civilian ID: $CIV_ID"

# 2. Inject the specific Warrant
# We want to ensure a specific known warrant exists for this task
WARRANT_REASON="Failure to Appear"
echo "Creating warrant for $WARRANT_REASON..."

# Delete any existing identical warrant to start fresh and clean
opencad_db_query "DELETE FROM ncic_warrants WHERE name_id=$CIV_ID AND warrant_name='$WARRANT_REASON'"

# Insert the target warrant
opencad_db_query "INSERT INTO ncic_warrants (name_id, warrant_name, issuing_agency, issued_date, expiration_date, status) VALUES ($CIV_ID, '$WARRANT_REASON', 'San Andreas District Court', CURDATE(), '2027-12-31', 'Active')"

# Get the ID of the warrant we just created
TARGET_WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE name_id=$CIV_ID AND warrant_name='$WARRANT_REASON' ORDER BY id DESC LIMIT 1")
echo "Target Warrant ID: $TARGET_WARRANT_ID"

# 3. Record Initial State
INITIAL_WARRANT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_warrants")
echo "$INITIAL_WARRANT_COUNT" > /tmp/initial_warrant_count.txt

# Save ID mappings for the export script
cat > /tmp/task_ids.json << EOF
{