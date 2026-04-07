#!/bin/bash
echo "=== Setting up hostname_standardization_remediation task ==="

source /workspace/scripts/task_utils.sh

API_URL="http://localhost:8000/api/v1"
TOKEN=$(get_api_token)

api_post() {
    curl -s -X POST "$API_URL/$1" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$2" | jq -r '.payload.id // .id // empty'
}

# 1. Clean up potential old data from previous runs
echo "Cleaning up any old task data..."
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'ASSET-800%'"
snipeit_db_query "DELETE FROM users WHERE username LIKE '%_eng' OR username LIKE '%_mkt'"
snipeit_db_query "DELETE FROM departments WHERE name IN ('Engineering', 'Marketing')"
snipeit_db_query "DELETE FROM locations WHERE name IN ('London', 'Berlin', 'Tokyo')"

# Safe creation helpers with DB fallback in case API validates too strictly
create_location() {
    local name="$1"
    local id=$(api_post "locations" "{\"name\":\"$name\"}")
    if [ -z "$id" ] || [ "$id" = "null" ]; then
        snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('$name', NOW(), NOW())"
        id=$(snipeit_db_query "SELECT id FROM locations WHERE name='$name' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    fi
    echo "$id"
}

create_department() {
    local name="$1"
    local id=$(api_post "departments" "{\"name\":\"$name\"}")
    if [ -z "$id" ] || [ "$id" = "null" ]; then
        snipeit_db_query "INSERT INTO departments (name, created_at, updated_at) VALUES ('$name', NOW(), NOW())"
        id=$(snipeit_db_query "SELECT id FROM departments WHERE name='$name' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    fi
    echo "$id"
}

create_user() {
    local fname="$1"
    local uname="$2"
    local dept="$3"
    local loc="$4"
    local id=$(api_post "users" "{\"first_name\":\"$fname\",\"username\":\"$uname\",\"password\":\"password\",\"department_id\":$dept,\"location_id\":$loc}")
    if [ -z "$id" ] || [ "$id" = "null" ]; then
        snipeit_db_query "INSERT INTO users (first_name, username, password, department_id, location_id, created_at, updated_at) VALUES ('$fname', '$uname', 'password', $dept, $loc, NOW(), NOW())"
        id=$(snipeit_db_query "SELECT id FROM users WHERE username='$uname' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    fi
    echo "$id"
}

# 2. Set up base taxonomy
echo "Creating Locations and Departments..."
L_LON=$(create_location "London")
L_BER=$(create_location "Berlin")
L_TYO=$(create_location "Tokyo")

D_ENG=$(create_department "Engineering")
D_MKT=$(create_department "Marketing")

# 3. Create Users
echo "Creating Users..."
U_ALICE=$(create_user "Alice" "alice_eng" "$D_ENG" "$L_LON")
U_BOB=$(create_user "Bob" "bob_eng" "$D_ENG" "$L_LON")
U_CHAR=$(create_user "Charlie" "char_eng" "$D_ENG" "$L_BER")
U_DAVE=$(create_user "Dave" "dave_eng" "$D_ENG" "$L_TYO")
U_EVE=$(create_user "Eve" "eve_mkt" "$D_MKT" "$L_LON")
U_FRANK=$(create_user "Frank" "frank_mkt" "$D_MKT" "$L_BER")

# 4. Get Status and Model IDs
S_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
S_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
M_LAPTOP=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Laptop%' OR name LIKE '%MacBook%' OR name LIKE '%ThinkPad%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$M_LAPTOP" ]; then M_LAPTOP=1; fi

# Helper to create asset and assign checkout
create_and_checkout() {
    local tag="$1"
    local name="$2"
    local user_id="$3"
    local loc_id="$4"
    
    local a_id=$(api_post "hardware" "{\"asset_tag\":\"$tag\",\"name\":\"$name\",\"model_id\":$M_LAPTOP,\"status_id\":$S_READY,\"rtd_location_id\":$loc_id}")
    
    if [ -z "$a_id" ] || [ "$a_id" = "null" ]; then
        snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, created_at, updated_at) VALUES ('$tag', '$name', $M_LAPTOP, $S_READY, $loc_id, NOW(), NOW())"
        a_id=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='$tag' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    fi

    if [ -n "$user_id" ] && [ "$user_id" != "null" ]; then
        local chk=$(curl -s -X POST "$API_URL/hardware/$a_id/checkout" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $TOKEN" \
            -d "{\"checkout_to_type\":\"user\",\"assigned_user\":$user_id}")
            
        # Fallback if checkout failed due to API validation rules
        if ! echo "$chk" | grep -q '"status":"success"'; then
            snipeit_db_query "UPDATE assets SET assigned_to=$user_id, assigned_type='App\\\\Models\\\\User', status_id=$S_DEPLOYED WHERE id=$a_id"
        fi
    fi
}

# 5. Inject Laptops
echo "Creating Assets and checking them out..."
# Target assets (Engineering)
create_and_checkout "ASSET-8001" "Alice-DevMac" "$U_ALICE" "$L_LON"
create_and_checkout "ASSET-8002" "Bob-ThinkPad" "$U_BOB" "$L_LON"
create_and_checkout "ASSET-8003" "Charlie-XPS" "$U_CHAR" "$L_BER"
create_and_checkout "ASSET-8004" "Dave-MBP" "$U_DAVE" "$L_TYO"

# Out-of-scope assets (Marketing)
create_and_checkout "ASSET-8005" "Eve-Air" "$U_EVE" "$L_LON"
create_and_checkout "ASSET-8006" "Frank-Surface" "$U_FRANK" "$L_BER"

# Out-of-scope asset (Unassigned)
create_and_checkout "ASSET-8007" "Spare-Eng-Laptop" "" "$L_LON"

# Let the database write completely finish
sleep 2

# 6. Record timestamps & launch application
date +%s > /tmp/task_start_time.txt

ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/hostname_setup_initial.png

echo "=== setup complete ==="