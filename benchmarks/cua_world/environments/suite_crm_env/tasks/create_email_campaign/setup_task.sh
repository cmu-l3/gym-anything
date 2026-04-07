#!/bin/bash
echo "=== Setting up Create Email Campaign task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# 2. Record initial campaign count
INITIAL_CAMPAIGN_COUNT=$(suitecrm_count "campaigns" "deleted=0")
echo "Initial campaign count: $INITIAL_CAMPAIGN_COUNT"
echo "$INITIAL_CAMPAIGN_COUNT" > /tmp/initial_campaign_count.txt
chmod 666 /tmp/initial_campaign_count.txt

# 3. Clean up any previous attempt with this exact name
suitecrm_db_query "UPDATE campaigns SET deleted=1 WHERE name='Q3 Industrial Equipment Launch'" 2>/dev/null || true

# 4. Create the target list "Q3 Industrial Partners" if it doesn't exist
TARGET_LIST_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM prospect_lists WHERE name='Q3 Industrial Partners' AND deleted=0" | tr -d '[:space:]')
if [ "$TARGET_LIST_EXISTS" = "0" ]; then
    echo "Creating target list 'Q3 Industrial Partners'..."
    # Generate UUID using python for reliability
    TARGET_LIST_ID=$(python3 -c "import uuid; print(uuid.uuid4().hex)")
    
    suitecrm_db_query "INSERT INTO prospect_lists (id, name, list_type, description, deleted, date_entered, date_modified, assigned_user_id)
        VALUES ('${TARGET_LIST_ID}', 'Q3 Industrial Partners', 'default', 'Target list of wholesale distribution partners for Q3 industrial equipment campaign', 0, NOW(), NOW(), '1')"

    # Link some existing contacts to this target list to make it realistic
    echo "Linking existing contacts to target list..."
    CONTACT_IDS=$(suitecrm_db_query "SELECT id FROM contacts WHERE deleted=0 LIMIT 8")
    for CID in $CONTACT_IDS; do
        CID=$(echo "$CID" | tr -d '[:space:]')
        if [ -n "$CID" ]; then
            LINK_ID=$(python3 -c "import uuid; print(uuid.uuid4().hex)")
            suitecrm_db_query "INSERT IGNORE INTO prospect_lists_prospects (id, prospect_list_id, related_id, related_type, date_modified, deleted)
                VALUES ('${LINK_ID}', '${TARGET_LIST_ID}', '${CID}', 'Contacts', NOW(), 0)" 2>/dev/null || true
        fi
    done
    echo "Linked contacts to target list"
else
    echo "Target list 'Q3 Industrial Partners' already exists"
    TARGET_LIST_ID=$(suitecrm_db_query "SELECT id FROM prospect_lists WHERE name='Q3 Industrial Partners' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
fi

echo "$TARGET_LIST_ID" > /tmp/target_list_id.txt
chmod 666 /tmp/target_list_id.txt
echo "Target list ID: $TARGET_LIST_ID"

# 5. Ensure Firefox is running, logged into SuiteCRM, and on the Home page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 6. Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="