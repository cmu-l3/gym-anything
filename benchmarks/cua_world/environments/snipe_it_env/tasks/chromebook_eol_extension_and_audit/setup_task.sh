#!/bin/bash
echo "=== Setting up chromebook_eol_extension_and_audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up any previous run data
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'ASSET-CB%'"
snipeit_db_query "DELETE FROM models WHERE name='Lenovo Chromebook 300e'"
snipeit_db_query "DELETE FROM status_labels WHERE name='Pending EOL Review'"
snipeit_db_query "DELETE FROM depreciations WHERE name='Chromebook 4-Year'"

# 2. Extract foundational IDs seeded by the environment
CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
MFG_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Lenovo' LIMIT 1" | tr -d '[:space:]')
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Create Status Label for Pending EOL Review using API
echo "  Creating 'Pending EOL Review' status..."
SL_PENDING_EOL=$(snipeit_api POST "statuslabels" '{"name":"Pending EOL Review","type":"undeployable","color":"#FF9800","show_in_nav":true}' | jq -r '.payload.id // .id')
if [ -z "$SL_PENDING_EOL" ] || [ "$SL_PENDING_EOL" == "null" ]; then
    echo "Fallback to DB insert for Status Label..."
    snipeit_db_query "INSERT INTO status_labels (name, type, color, show_in_nav, created_at, updated_at) VALUES ('Pending EOL Review', 'undeployable', '#FF9800', 1, NOW(), NOW())"
    SL_PENDING_EOL=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Pending EOL Review' LIMIT 1" | tr -d '[:space:]')
fi

# Create Asset Model using API
echo "  Creating Asset Model..."
MODEL_ID=$(snipeit_api POST "models" "{\"name\":\"Lenovo Chromebook 300e\",\"category_id\":$CAT_ID,\"manufacturer_id\":$MFG_ID,\"eol\":36}" | jq -r '.payload.id // .id')
if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" == "null" ]; then
    echo "Fallback to DB insert for Model..."
    snipeit_db_query "INSERT INTO models (name, category_id, manufacturer_id, eol, created_at, updated_at) VALUES ('Lenovo Chromebook 300e', $CAT_ID, $MFG_ID, 36, NOW(), NOW())"
    MODEL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='Lenovo Chromebook 300e' LIMIT 1" | tr -d '[:space:]')
fi

# 3. Create Chromebook Assets
echo "  Injecting Chromebook assets..."

# Helper to create asset via API
create_asset() {
    local tag="$1"
    local name="$2"
    local status_id="$3"
    local date="$4"
    local notes="$5"
    
    local payload="{\"asset_tag\":\"$tag\",\"name\":\"$name\",\"model_id\":$MODEL_ID,\"status_id\":$status_id,\"purchase_date\":\"$date\",\"notes\":\"$notes\"}"
    snipeit_api POST "hardware" "$payload" > /dev/null
}

# Assets that will expire or remain valid based on 48m threshold against 2026-03-08
create_asset "ASSET-CB001" "Student Chromebook 01" "$SL_PENDING_EOL" "2022-10-01" "Pending review."
create_asset "ASSET-CB002" "Student Chromebook 02" "$SL_PENDING_EOL" "2021-12-01" "Pending review."
create_asset "ASSET-CB003" "Student Chromebook 03" "$SL_PENDING_EOL" "2022-08-15" "Pending review."
create_asset "ASSET-CB004" "Student Chromebook 04" "$SL_PENDING_EOL" "2022-01-10" "Pending review."
create_asset "ASSET-CB005" "Student Chromebook 05" "$SL_PENDING_EOL" "2023-01-01" "Pending review."

# Control Asset (Must NOT be modified)
create_asset "ASSET-CB006" "Teacher Chromebook 06" "$SL_READY" "2023-05-01" "Control asset - active."

sleep 2

# 4. Record task start state
date +%s > /tmp/task_start_time.txt

# 5. Ensure Firefox is running and focused
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/chromebook_eol_initial.png

echo "=== Setup Complete ==="