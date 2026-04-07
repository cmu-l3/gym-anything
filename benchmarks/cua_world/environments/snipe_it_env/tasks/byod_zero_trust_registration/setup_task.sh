#!/bin/bash
set -e
echo "=== Setting up byod_zero_trust_registration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up any pre-existing BYOD state from previous runs
echo "--- Cleaning up any existing task data ---"
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'BYOD-%'"
snipeit_db_query "DELETE FROM models WHERE name='Personal Smartphone'"
snipeit_db_query "DELETE FROM status_labels WHERE name='BYOD - Approved'"
snipeit_db_query "DELETE FROM custom_field_custom_fieldset WHERE custom_fieldset_id IN (SELECT id FROM custom_fieldsets WHERE name='BYOD Device Info')"
snipeit_db_query "DELETE FROM custom_fieldsets WHERE name='BYOD Device Info'"
snipeit_db_query "DELETE FROM custom_fields WHERE name IN ('Network MAC Address', 'Mobile OS Version')"

# 2. Ensure prerequisites exist (Users, Category, Manufacturer)
echo "--- Ensuring prerequisites (Users, Category, Manufacturer) ---"

# Create users if they don't exist
create_user_if_missing() {
    local fname=$1; local lname=$2; local uname=$3
    local exists=$(snipeit_db_query "SELECT id FROM users WHERE username='$uname' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    if [ -z "$exists" ]; then
        snipeit_api POST "users" "{\"first_name\":\"$fname\",\"last_name\":\"$lname\",\"username\":\"$uname\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"email\":\"$uname@example.com\",\"activated\":1}" > /dev/null
    fi
}
create_user_if_missing "John" "Smith" "jsmith"
create_user_if_missing "Mary" "Jones" "mjones"
create_user_if_missing "Tom" "Lee" "tlee"

# Ensure category exists
CAT_EXISTS=$(snipeit_db_query "SELECT id FROM categories WHERE name='Mobile Devices' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$CAT_EXISTS" ]; then
    snipeit_api POST "categories" '{"name":"Mobile Devices","category_type":"asset","use_default_eula":0}' > /dev/null
fi

# Ensure manufacturer exists
MFG_EXISTS=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Generic' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$MFG_EXISTS" ]; then
    snipeit_api POST "manufacturers" '{"name":"Generic"}' > /dev/null
fi

# 3. Record Baseline State
echo "--- Recording baseline state ---"
INITIAL_ASSET_COUNT=$(get_asset_count)
echo "$INITIAL_ASSET_COUNT" > /tmp/initial_asset_count.txt

MAX_ASSET_ID=$(snipeit_db_query "SELECT COALESCE(MAX(id), 0) FROM assets" | tr -d '[:space:]')
echo "$MAX_ASSET_ID" > /tmp/max_asset_id_start.txt

# Timestamp
date +%s > /tmp/task_start_time.txt

# 4. Launch Browser
echo "--- Launching Snipe-IT in Firefox ---"
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="