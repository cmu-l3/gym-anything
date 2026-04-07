#!/bin/bash
set -e
echo "=== Setting up Phone Number Normalization Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

echo "Preparing test data in DrTuxTest database..."

# 1. Create a snapshot of the table structure if needed (not strictly necessary as we assume DrTuxTest exists)
# 2. Inject specific test cases into fchpat and IndexNomPrenom
# We use existing demo data but update specific rows to have messy phone numbers
# or insert new ones if the table is empty.

# Helper function to insert test patient
insert_test_patient() {
    local guid="$1"
    local nom="$2"
    local phone="$3"
    
    # Delete if exists
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$guid'" 2>/dev/null || true
    
    # Insert with specific phone format
    # We use minimal fields required for the record to exist
    mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Tel1, FchPat_Nee, FchPat_Sexe) VALUES ('$guid', '$nom', '$phone', '1980-01-01', 'F')" 2>/dev/null || true
}

# Test Case 1: Spaces (Should be cleaned to 0612345678)
insert_test_patient "TEST-GUID-SPACES" "TEST_SPACES" "06 12 34 56 78"

# Test Case 2: Dots (Should be cleaned to 0491234567)
insert_test_patient "TEST-GUID-DOTS" "TEST_DOTS" "04.91.23.45.67"

# Test Case 3: Dashes (Should be cleaned to 0145678901)
insert_test_patient "TEST-GUID-DASHES" "TEST_DASHES" "01-45-67-89-01"

# Test Case 4: Short/Invalid (Should appear in report)
insert_test_patient "TEST-GUID-SHORT" "TEST_SHORT" "061234"

# Test Case 5: Text (Should appear in report)
insert_test_patient "TEST-GUID-TEXT" "TEST_TEXT" "Pas de telephone"

# Test Case 6: Already Clean (Should remain unchanged)
insert_test_patient "TEST-GUID-CLEAN" "TEST_CLEAN" "0987654321"

# Record initial count of records with separators
INITIAL_DIRTY_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_Tel1 LIKE '% %' OR FchPat_Tel1 LIKE '%.%' OR FchPat_Tel1 LIKE '%-%' OR FchPat_Tel1 LIKE '%/%'" 2>/dev/null)
echo "$INITIAL_DIRTY_COUNT" > /tmp/initial_dirty_count.txt

# Record initial count of valid 10-digit numbers
INITIAL_VALID_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_Tel1 REGEXP '^[0-9]{10}$'" 2>/dev/null)
echo "$INITIAL_VALID_COUNT" > /tmp/initial_valid_count.txt

echo "Injected test data."
echo "Initial dirty records: $INITIAL_DIRTY_COUNT"
echo "Initial valid records: $INITIAL_VALID_COUNT"

# Ensure MedinTux Manager is NOT running (to avoid lock issues, though MySQL handles concurrency)
# But strictly, the task description says "MedinTux Manager may be open".
# Let's start it to simulate a live environment, but verify DB interaction.
# Launching MedinTux (optional for this specific DB task, but good for realism)
if ! pgrep -f "Manager.exe" > /dev/null; then
    /workspace/scripts/task_utils.sh launch_medintux_manager > /dev/null 2>&1 &
fi

# Take initial screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="