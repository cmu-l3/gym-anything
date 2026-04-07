#!/bin/bash
echo "=== Setting up component_tracking_server_upgrade task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Record initial component count
INITIAL_COMPONENT_COUNT=$(snipeit_count "components" "deleted_at IS NULL" 2>/dev/null || echo "0")
echo "$INITIAL_COMPONENT_COUNT" > /tmp/initial_component_count.txt

# 3. Setup prerequisites using API
API_TOKEN=$(get_api_token)
if [ -z "$API_TOKEN" ]; then
    echo "ERROR: No API token available"
    exit 1
fi

SNIPEIT_URL="http://localhost:8000"
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    curl -s -X "$method" \
        "${SNIPEIT_URL}/api/v1/${endpoint}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -d "$data" 2>/dev/null
}

# Find or create Austin DC location
AUSTIN_LOC_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Austin DC' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$AUSTIN_LOC_ID" ]; then
    RESULT=$(api_call POST "locations" '{"name":"Austin DC","address":"100 Congress Ave","city":"Austin","state":"TX","country":"US","zip":"78701"}')
    AUSTIN_LOC_ID=$(echo "$RESULT" | jq -r '.payload.id // empty')
fi
echo "$AUSTIN_LOC_ID" > /tmp/austin_loc_id.txt

# Find a server model ID (or create one)
SERVER_MODEL_ID=$(snipeit_db_query "SELECT m.id FROM models m JOIN categories c ON m.category_id=c.id WHERE c.name='Servers' AND m.deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$SERVER_MODEL_ID" ]; then
    SERVER_CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Servers' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    DELL_MFR_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    RESULT=$(api_call POST "models" "{\"name\":\"PowerEdge R740\",\"category_id\":${SERVER_CAT_ID:-1},\"manufacturer_id\":${DELL_MFR_ID:-1},\"model_number\":\"R740\"}")
    SERVER_MODEL_ID=$(echo "$RESULT" | jq -r '.payload.id // empty')
fi

# Find Ready to Deploy status
RTD_STATUS_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$RTD_STATUS_ID" ]; then
    RTD_STATUS_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE pending='0' AND deployable='1' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
fi

# 4. Create server assets for the upgrade project
# SVR-UPG-001
EXISTING_1=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='SVR-UPG-001' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ -z "$EXISTING_1" ]; then
    api_call POST "hardware" "{
        \"asset_tag\": \"SVR-UPG-001\",
        \"name\": \"Web Server Rack A-01\",
        \"model_id\": ${SERVER_MODEL_ID},
        \"status_id\": ${RTD_STATUS_ID},
        \"rtd_location_id\": ${AUSTIN_LOC_ID},
        \"serial\": \"SVRUPG001SN2024\"
    }"
fi
SVR1_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='SVR-UPG-001' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
echo "$SVR1_ID" > /tmp/svr1_asset_id.txt

# SVR-UPG-002
EXISTING_2=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='SVR-UPG-002' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ -z "$EXISTING_2" ]; then
    api_call POST "hardware" "{
        \"asset_tag\": \"SVR-UPG-002\",
        \"name\": \"Database Server Rack B-03\",
        \"model_id\": ${SERVER_MODEL_ID},
        \"status_id\": ${RTD_STATUS_ID},
        \"rtd_location_id\": ${AUSTIN_LOC_ID},
        \"serial\": \"SVRUPG002SN2024\"
    }"
fi
SVR2_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='SVR-UPG-002' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
echo "$SVR2_ID" > /tmp/svr2_asset_id.txt

# Remove any existing test components
snipeit_db_query "DELETE FROM components WHERE name LIKE '%Samsung%32GB%'"
snipeit_db_query "DELETE FROM components WHERE name LIKE '%Kingston%64GB%'"
snipeit_db_query "DELETE FROM categories WHERE name='Server Memory' AND category_type='component'"

# 5. UI Setup
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="