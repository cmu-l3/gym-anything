#!/bin/bash
echo "=== Setting up expunge_arrest_record task ==="

source /workspace/scripts/task_utils.sh

# 1. Inject Seed Data
echo "Injecting task-specific data..."

# Clean up any previous run data to ensure fresh state
opencad_db_query "DELETE FROM ncic_arrests WHERE name_id IN (SELECT id FROM ncic_names WHERE name IN ('Elias Thorne', 'Sarah Connor'));"
opencad_db_query "DELETE FROM ncic_names WHERE name IN ('Elias Thorne', 'Sarah Connor');"

# Insert Civilian Identities (ncic_names)
# Note: ID is auto-increment, so we let DB handle it
opencad_db_query "INSERT INTO ncic_names (submittedByName, submittedById, name, dob, address, gender, race, dl_status, hair_color, build, weapon_permit, deceased) VALUES
('Admin User', '1A-01', 'Elias Thorne', '1980-05-12', '442 Industrial Ave', 'Male', 'Caucasian', 'Valid', 'Brown', 'Average', 'Unobtained', 'NO'),
('Admin User', '1A-01', 'Sarah Connor', '1984-08-29', '1984 Pico Blvd', 'Female', 'Caucasian', 'Suspended', 'Blonde', 'Average', 'Unobtained', 'NO');"

# Get IDs for FK references
ELIAS_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Elias Thorne' LIMIT 1")
SARAH_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Sarah Connor' LIMIT 1")

# Insert Arrest Records (ncic_arrests)
# Target Record
opencad_db_query "INSERT INTO ncic_arrests (name_id, arrest_reason, arrest_fine, issued_date, issued_by) VALUES
($ELIAS_ID, 'Criminal Trespass', '500.00', '2025-10-10', 'Officer John Doe 1A-01');"

# Distractor Record (should NOT be deleted)
opencad_db_query "INSERT INTO ncic_arrests (name_id, arrest_reason, arrest_fine, issued_date, issued_by) VALUES
($SARAH_ID, 'Destruction of Property', '5000.00', '2025-10-11', 'Officer T-1000 1A-02');"

echo "Data injection complete."

# 2. Record Initial State
INITIAL_ARREST_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_arrests")
echo "${INITIAL_ARREST_COUNT:-0}" | sudo tee /tmp/initial_arrest_count > /dev/null
sudo chmod 666 /tmp/initial_arrest_count

# Record specific counts to verify setup
TARGET_SETUP_CHECK=$(opencad_db_query "SELECT COUNT(*) FROM ncic_arrests WHERE name_id=$ELIAS_ID")
if [ "$TARGET_SETUP_CHECK" -ne "1" ]; then
    echo "ERROR: Target arrest record not created successfully."
    exit 1
fi
