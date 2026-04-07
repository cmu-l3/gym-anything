#!/bin/bash
echo "=== Setting up create_custom_relationship_m2m task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous artifacts (if env was reused)
echo "Cleaning up any existing custom relationships between Opportunities and Bugs..."
# Drop custom join tables
EXISTING_TABLES=$(suitecrm_db_query "SELECT TABLE_NAME FROM information_schema.tables WHERE table_schema='suitecrm' AND (table_name LIKE '%opportunities_bugs%' OR table_name LIKE '%bugs_opportunities%') AND table_name LIKE '%\_c'")
for t in $EXISTING_TABLES; do
    echo "Dropping old join table: $t"
    suitecrm_db_query "DROP TABLE IF EXISTS $t"
done
# Remove relationship metadata
suitecrm_db_query "DELETE FROM relationships WHERE (lhs_module='Opportunities' AND rhs_module='Bugs') OR (lhs_module='Bugs' AND rhs_module='Opportunities')"

# 3. Insert Target Data
OPP_ID="opp-meridian-1234"
BUG_ID="bug-mobile-5678"

echo "Provisioning target Opportunity and Bug records..."
# Remove if they already exist
suitecrm_db_query "DELETE FROM opportunities WHERE id='$OPP_ID'"
suitecrm_db_query "DELETE FROM bugs WHERE id='$BUG_ID'"

# Insert target Opportunity
suitecrm_db_query "INSERT INTO opportunities (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('$OPP_ID', 'Enterprise License - Meridian Tech', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 0)"

# Insert target Bug (Note: 'bugs' table uses 'name' for the bug subject)
suitecrm_db_query "INSERT INTO bugs (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, status, priority, type) VALUES ('$BUG_ID', 'UI unresponsive on mobile', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 0, 'New', 'High', 'Defect')"

# 4. Ensure logged in and navigate to Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== setup complete ==="