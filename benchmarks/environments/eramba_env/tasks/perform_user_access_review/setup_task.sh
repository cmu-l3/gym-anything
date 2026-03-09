#!/bin/bash
set -e
echo "=== Setting up task: Perform User Access Review ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Seed Prerequisites: Asset
# ---------------------------------------------------------------
echo "--- Seeding Asset ---"
# Create Asset if it doesn't exist
# Asset Type 1 = Information Asset (standard in Eramba default install)
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO assets (name, asset_type_id, description, created, modified) 
     SELECT 'HR Employee Database', 1, 'Primary database for employee records', NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM assets WHERE name='HR Employee Database');"

ASSET_ID=$(eramba_db_query "SELECT id FROM assets WHERE name='HR Employee Database' LIMIT 1;")
echo "  Asset ID: $ASSET_ID"

# ---------------------------------------------------------------
# 2. Seed Account Review Container
# ---------------------------------------------------------------
echo "--- Seeding Account Review ---"
# Status 1 usually implies 'Planned' or 'In Progress' depending on config, setting to 1 to ensure visibility
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO account_reviews (name, asset_id, description, status, deadline, created, modified) 
     SELECT 'Q3 2025 HR DB Access Review', $ASSET_ID, 'Quarterly access review for HR system', 1, DATE_ADD(NOW(), INTERVAL 7 DAY), NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM account_reviews WHERE name='Q3 2025 HR DB Access Review');"

REVIEW_ID=$(eramba_db_query "SELECT id FROM account_reviews WHERE name='Q3 2025 HR DB Access Review' LIMIT 1;")
echo "  Review ID: $REVIEW_ID"

# ---------------------------------------------------------------
# 3. Seed Account Review Items (Users)
# ---------------------------------------------------------------
echo "--- Seeding Review Items ---"
# Clear existing items for this review to ensure clean state (idempotency)
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "DELETE FROM account_review_items WHERE account_review_id=$REVIEW_ID;"

# Insert 3 items. 
# Notes on fields: 
# 'account' is the username/identifier. 
# 'user_id' is for internal eramba users, NULL for external accounts.
# 'status' is NULL initially (Pending).
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO account_review_items (account_review_id, account, name, created, modified) VALUES 
    ($REVIEW_ID, 'alice.admin', 'Alice Administrator', NOW(), NOW()),
    ($REVIEW_ID, 'bob.user', 'Bob User', NOW(), NOW()),
    ($REVIEW_ID, 'charlie.vendor', 'Charlie Vendor', NOW(), NOW());"

echo "  Seeded 3 items (alice.admin, bob.user, charlie.vendor)"

# ---------------------------------------------------------------
# 4. Record Initial State
# ---------------------------------------------------------------
# Count items with non-null status (should be 0)
INITIAL_COMPLETED_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM account_review_items WHERE account_review_id=$REVIEW_ID AND status IS NOT NULL;")
echo "$INITIAL_COMPLETED_COUNT" > /tmp/initial_completed_count.txt

# ---------------------------------------------------------------
# 5. Launch Application
# ---------------------------------------------------------------
echo "--- Launching Firefox ---"
# Direct to Account Reviews page to save agent time
ensure_firefox_eramba "http://localhost:8080/account_reviews/index"
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="