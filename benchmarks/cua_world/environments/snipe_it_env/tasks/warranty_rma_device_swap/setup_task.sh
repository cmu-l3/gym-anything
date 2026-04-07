#!/bin/bash
echo "=== Setting up warranty_rma_device_swap task ==="
source /workspace/scripts/task_utils.sh

# Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 1. Fetch required database entity IDs
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

MDL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Latitude%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_ID" ]; then
    MDL_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
fi

echo "Using Model ID: $MDL_ID and Status ID: $SL_READY_ID"

# 2. Insert test users
snipeit_db_query "INSERT IGNORE INTO users (first_name, last_name, username, email, permissions, activated, created_at, updated_at) VALUES ('John', 'Doe', 'jdoe', 'jdoe@example.com', '{\"user\":1}', 1, NOW(), NOW());"
snipeit_db_query "INSERT IGNORE INTO users (first_name, last_name, username, email, permissions, activated, created_at, updated_at) VALUES ('Alice', 'Smith', 'asmith', 'asmith@example.com', '{\"user\":1}', 1, NOW(), NOW());"
snipeit_db_query "INSERT IGNORE INTO users (first_name, last_name, username, email, permissions, activated, created_at, updated_at) VALUES ('Bruce', 'Wayne', 'bwayne', 'bwayne@example.com', '{\"user\":1}', 1, NOW(), NOW());"

USER1_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='jdoe' LIMIT 1" | tr -d '[:space:]')
USER2_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='asmith' LIMIT 1" | tr -d '[:space:]')
USER3_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='bwayne' LIMIT 1" | tr -d '[:space:]')

echo "Using User IDs: $USER1_ID, $USER2_ID, $USER3_ID"

# 3. Cleanup any potential leftover assets from previous runs
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'LPT-ERR-%' OR asset_tag LIKE 'LPT-REP-%'"

# 4. Randomize dates and costs to prevent hardcoding / gaming
COST1="$(shuf -i 1000-1499 -n 1).00"
COST2="$(shuf -i 1500-1999 -n 1).00"
COST3="$(shuf -i 800-999 -n 1).00"

DATE1="$(shuf -i 2021-2023 -n 1)-$(shuf -i 1-12 -n 1 | awk '{printf "%02d", $1}')-15"
DATE2="$(shuf -i 2021-2023 -n 1)-$(shuf -i 1-12 -n 1 | awk '{printf "%02d", $1}')-10"
DATE3="$(shuf -i 2021-2023 -n 1)-$(shuf -i 1-12 -n 1 | awk '{printf "%02d", $1}')-20"

echo "Creating defective assets..."

# Asset 1
snipeit_api POST "hardware" "{\"asset_tag\":\"LPT-ERR-01\",\"name\":\"Failing Laptop 1\",\"model_id\":$MDL_ID,\"status_id\":$SL_READY_ID,\"serial\":\"OLD-SN-01\",\"purchase_date\":\"$DATE1\",\"purchase_cost\":$COST1}" > /dev/null
ASSET1_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='LPT-ERR-01' LIMIT 1" | tr -d '[:space:]')
snipeit_db_query "UPDATE assets SET assigned_to=$USER1_ID, assigned_type='App\\\\Models\\\\User' WHERE id=$ASSET1_ID"

# Asset 2
snipeit_api POST "hardware" "{\"asset_tag\":\"LPT-ERR-02\",\"name\":\"Failing Laptop 2\",\"model_id\":$MDL_ID,\"status_id\":$SL_READY_ID,\"serial\":\"OLD-SN-02\",\"purchase_date\":\"$DATE2\",\"purchase_cost\":$COST2}" > /dev/null
ASSET2_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='LPT-ERR-02' LIMIT 1" | tr -d '[:space:]')
snipeit_db_query "UPDATE assets SET assigned_to=$USER2_ID, assigned_type='App\\\\Models\\\\User' WHERE id=$ASSET2_ID"

# Asset 3
snipeit_api POST "hardware" "{\"asset_tag\":\"LPT-ERR-03\",\"name\":\"Failing Laptop 3\",\"model_id\":$MDL_ID,\"status_id\":$SL_READY_ID,\"serial\":\"OLD-SN-03\",\"purchase_date\":\"$DATE3\",\"purchase_cost\":$COST3}" > /dev/null
ASSET3_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='LPT-ERR-03' LIMIT 1" | tr -d '[:space:]')
snipeit_db_query "UPDATE assets SET assigned_to=$USER3_ID, assigned_type='App\\\\Models\\\\User' WHERE id=$ASSET3_ID"

# 5. Export Baseline configuration JSON
cat << EOF > /tmp/rma_baseline.json
{
  "LPT-ERR-01": {"model_id": $MDL_ID, "cost": $COST1, "date": "$DATE1", "user_id": $USER1_ID, "username": "jdoe"},
  "LPT-ERR-02": {"model_id": $MDL_ID, "cost": $COST2, "date": "$DATE2", "user_id": $USER2_ID, "username": "asmith"},
  "LPT-ERR-03": {"model_id": $MDL_ID, "cost": $COST3, "date": "$DATE3", "user_id": $USER3_ID, "username": "bwayne"}
}
EOF

# 6. Ensure Firefox is running and at standard start state
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/rma_initial.png

echo "=== warranty_rma_device_swap task setup complete ==="