#!/bin/bash
echo "=== Setting up hardware_salvage_component_harvesting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Fetch necessary IDs for inserting test data
SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
if [ -z "$SL_DEPLOYED" ]; then
    SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels LIMIT 1" | tr -d '[:space:]')
fi

MDL_WS=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Precision%' OR name LIKE '%OptiPlex%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_WS" ]; then
    MDL_WS=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
fi

LOC_HQ=$(snipeit_db_query "SELECT id FROM locations LIMIT 1" | tr -d '[:space:]')
if [ -z "$LOC_HQ" ]; then
    LOC_HQ="NULL"
fi

# 2. Ensure Component Categories exist
snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, created_at, updated_at) VALUES ('Graphics Cards', 'component', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, created_at, updated_at) VALUES ('Memory', 'component', NOW(), NOW())"

# 3. Clean up any existing task assets/components to ensure a clean state
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('ASSET-ENG-99', 'ASSET-ENG-42')"
snipeit_db_query "DELETE FROM components WHERE name LIKE '%NVIDIA RTX A6000%' OR name LIKE '%128GB DDR4 ECC RAM Kit%'"

# 4. Inject ASSET-ENG-99 (The dead workstation)
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, serial, purchase_date, purchase_cost, created_at, updated_at) VALUES ('ASSET-ENG-99', 'Dell Precision 7920 - Render Station', $MDL_WS, $SL_DEPLOYED, $LOC_HQ, 'DP7920-LIQ-FAIL', '2023-01-15', 8500.00, NOW(), NOW())"

# 5. Inject ASSET-ENG-42 (The target workstation)
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, serial, purchase_date, purchase_cost, created_at, updated_at) VALUES ('ASSET-ENG-42', 'Dell Precision 7920 - CAD Station', $MDL_WS, $SL_DEPLOYED, $LOC_HQ, 'DP7920-CAD-WORK', '2023-05-10', 6500.00, NOW(), NOW())"

# 6. Pre-flight checks & browser launch
ensure_firefox_snipeit
sleep 2

# Navigate to Dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="