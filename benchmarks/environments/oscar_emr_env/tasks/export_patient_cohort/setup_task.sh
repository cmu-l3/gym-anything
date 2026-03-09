#!/bin/bash
# Setup script for Export Patient Cohort task
# Seeds the database with specific patients born in and around 2020

set -e
echo "=== Setting up Export Patient Cohort Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous output
rm -f "/home/ga/Documents/2020_cohort.csv"

# 2. Seed Database
# We need specific patients to verify the date filtering logic
# Targets (Born 2020): Lucas Target, Sophia Target
# Distractors (Born 2019, 2021): Liam Older, Olivia Younger

echo "Seeding patient data..."

# Helper to insert patient if not exists
insert_patient() {
    local fname="$1"
    local lname="$2"
    local y="$3"
    local m="$4"
    local d="$5"
    
    # Check existence
    local count=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$fname' AND last_name='$lname'" || echo "0")
    
    if [ "${count:-0}" -eq 0 ]; then
        echo "Inserting $fname $lname ($y-$m-$d)..."
        # Using 999998 (oscardoc) as provider
        oscar_query "INSERT INTO demographic (
            last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, 
            phone, provider_no, patient_status, lastUpdateDate
        ) VALUES (
            '$lname', '$fname', 'M', '$y', '$m', '$d', 
            '555-0199', '999998', 'AC', NOW()
        );" 2>/dev/null || true
    else
        echo "Patient $fname $lname already exists."
    fi
}

insert_patient "Lucas" "Target" "2020" "03" "15"
insert_patient "Sophia" "Target" "2020" "11" "20"
insert_patient "Liam" "Older" "2019" "12" "31"
insert_patient "Olivia" "Younger" "2021" "01" "01"

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Prepare Browser
ensure_firefox_on_oscar

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="