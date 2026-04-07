#!/bin/bash
echo "=== Setting up link_opps_to_campaign task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (used for anti-gaming in the verifier)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Clean up any existing records with these names to ensure clean state
# ---------------------------------------------------------------
suitecrm_db_query "DELETE FROM campaigns WHERE name='Spring Tech Conference';"
suitecrm_db_query "DELETE FROM opportunities WHERE name IN ('Alpha Tech Upgrade', 'Beta Corp License', 'Gamma LLC Support');"

# ---------------------------------------------------------------
# 2. Create the target Campaign (missing actual_cost)
# ---------------------------------------------------------------
CAMP_ID=$(cat /proc/sys/kernel/random/uuid)
suitecrm_db_query "INSERT INTO campaigns (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, status, campaign_type, actual_cost) 
VALUES ('$CAMP_ID', 'Spring Tech Conference', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 0, 'Active', 'Trade Show', NULL);"

echo "Created target Campaign: Spring Tech Conference ($CAMP_ID)"

# ---------------------------------------------------------------
# 3. Create the target Opportunities (unlinked from campaign)
# ---------------------------------------------------------------
for OPP_NAME in "Alpha Tech Upgrade" "Beta Corp License" "Gamma LLC Support"; do
    OPP_ID=$(cat /proc/sys/kernel/random/uuid)
    # Insert with empty campaign_id
    suitecrm_db_query "INSERT INTO opportunities (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, amount, sales_stage, campaign_id) 
    VALUES ('$OPP_ID', '$OPP_NAME', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 0, 50000, 'Prospecting', '');"
    echo "Created target Opportunity: $OPP_NAME ($OPP_ID)"
done

# ---------------------------------------------------------------
# 4. Navigate Firefox to SuiteCRM and take baseline screenshot
# ---------------------------------------------------------------
# Ensure Firefox is open and logged into SuiteCRM, starting at the Home page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 4

take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="