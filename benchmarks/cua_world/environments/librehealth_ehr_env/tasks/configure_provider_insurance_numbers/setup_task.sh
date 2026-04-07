#!/bin/bash
set -e
echo "=== Setting up task: configure_provider_insurance_numbers@1 ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for LibreHealth to be ready
wait_for_librehealth 60

# 3. Ensure "Blue Cross Blue Shield" exists in the database
echo "Checking for insurance carrier..."
IC_CHECK=$(librehealth_query "SELECT count(*) FROM insurance_companies WHERE name LIKE '%Blue Cross Blue Shield%'")

if [ "$IC_CHECK" -eq "0" ]; then
    echo "Seeding 'Blue Cross Blue Shield'..."
    NEXT_IC_ID=$(librehealth_query "SELECT COALESCE(MAX(id),0)+1 FROM insurance_companies")
    librehealth_query "INSERT INTO insurance_companies (id, name, attn, cms_id, ins_type_code) VALUES ($NEXT_IC_ID, 'Blue Cross Blue Shield', 'Claims Dept', 'BCBS01', 1)"
else
    echo "Carrier 'Blue Cross Blue Shield' already exists."
fi

# 4. Clear any PRE-EXISTING insurance numbers for Admin + BCBS to ensure clean slate
# Get IDs
ADMIN_ID=$(librehealth_query "SELECT id FROM users WHERE username='admin' LIMIT 1")
BCBS_ID=$(librehealth_query "SELECT id FROM insurance_companies WHERE name LIKE '%Blue Cross Blue Shield%' LIMIT 1")

if [ -n "$ADMIN_ID" ] && [ -n "$BCBS_ID" ]; then
    echo "Clearing old insurance numbers for Admin (ID: $ADMIN_ID) and BCBS (ID: $BCBS_ID)..."
    librehealth_query "DELETE FROM insurance_numbers WHERE provider_id='$ADMIN_ID' AND insurance_company_id='$BCBS_ID'"
fi

# 5. Record initial max ID for anti-gaming (to prove new record was created)
MAX_ID=$(librehealth_query "SELECT COALESCE(MAX(id), 0) FROM insurance_numbers")
echo "$MAX_ID" > /tmp/initial_max_id.txt

# 6. Prepare browser
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="