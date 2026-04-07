#!/bin/bash
echo "=== Setting up departmental_license_reallocation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "--- Creating departments, users, and licenses via API ---"

# Get category ID for Software
CAT_LIC=$(snipeit_api POST "categories" '{"name":"Software Task","category_type":"license"}' | jq -r '.payload.id // .id // empty')
if [ -z "$CAT_LIC" ] || [ "$CAT_LIC" == "null" ]; then
    CAT_LIC=$(snipeit_db_query "SELECT id FROM categories WHERE category_type='license' LIMIT 1" | tr -d '[:space:]')
fi

# Create Departments
DEP_CREATIVE=$(snipeit_api POST "departments" '{"name":"Creative"}' | jq -r '.payload.id // .id // empty')
DEP_MARKETING=$(snipeit_api POST "departments" '{"name":"Marketing"}' | jq -r '.payload.id // .id // empty')
DEP_SALES=$(snipeit_api POST "departments" '{"name":"Sales"}' | jq -r '.payload.id // .id // empty')
DEP_FINANCE=$(snipeit_api POST "departments" '{"name":"Finance"}' | jq -r '.payload.id // .id // empty')
DEP_HR=$(snipeit_api POST "departments" '{"name":"HR"}' | jq -r '.payload.id // .id // empty')

# Create Users
create_user() {
    local first="$1"
    local last="$2"
    local username="$3"
    local dep_id="$4"
    snipeit_api POST "users" "{\"first_name\":\"$first\",\"last_name\":\"$last\",\"username\":\"$username\",\"password\":\"password\",\"password_confirmation\":\"password\",\"department_id\":$dep_id}" | jq -r '.payload.id // .id // empty'
}

U_C1=$(create_user "Alice" "Art" "aart" $DEP_CREATIVE)
U_C2=$(create_user "Bob" "Brush" "bbrush" $DEP_CREATIVE)
U_C3=$(create_user "Charlie" "Canvas" "ccanvas" $DEP_CREATIVE)
U_C4=$(create_user "Diana" "Design" "ddesign" $DEP_CREATIVE)

U_M1=$(create_user "Eve" "Market" "emarket" $DEP_MARKETING)
U_M2=$(create_user "Frank" "Funnel" "ffunnel" $DEP_MARKETING)
U_M3=$(create_user "Grace" "Growth" "ggrowth" $DEP_MARKETING)
U_M4=$(create_user "Heidi" "Hype" "hhype" $DEP_MARKETING)

U_S1=$(create_user "Ivan" "Invoice" "iinvoice" $DEP_SALES)
U_S2=$(create_user "Judy" "Jingle" "jjingle" $DEP_SALES)
U_S3=$(create_user "Karl" "Klose" "kklose" $DEP_SALES)

U_F1=$(create_user "Liam" "Ledger" "lledger" $DEP_FINANCE)
U_F2=$(create_user "Mia" "Money" "mmoney" $DEP_FINANCE)

U_H1=$(create_user "Nina" "Network" "nnetwork" $DEP_HR)
U_H2=$(create_user "Oscar" "Offer" "ooffer" $DEP_HR)

# Create Licenses
LIC_ADOBE=$(snipeit_api POST "licenses" "{\"name\":\"Adobe Creative Cloud All Apps\",\"seats\":10,\"category_id\":$CAT_LIC}" | jq -r '.payload.id // .id // empty')
LIC_MS365=$(snipeit_api POST "licenses" "{\"name\":\"Microsoft 365\",\"seats\":50,\"category_id\":$CAT_LIC}" | jq -r '.payload.id // .id // empty')

echo "Adobe License ID: $LIC_ADOBE"
echo "MS365 License ID: $LIC_MS365"

# Save IDs for export script
echo "$LIC_ADOBE" > /tmp/license_adobe_id.txt
echo "$LIC_MS365" > /tmp/license_ms365_id.txt

# Wait a moment for seats to be created
sleep 2

# Helper to checkout license
checkout_license() {
    local lic_id="$1"
    local user_id="$2"
    snipeit_api POST "licenses/$lic_id/checkout" "{\"assigned_to\":$user_id}" > /dev/null
}

echo "Checking out initial Adobe seats (messy state)..."
# 3 Authorized Users
checkout_license $LIC_ADOBE $U_C1
checkout_license $LIC_ADOBE $U_C2
checkout_license $LIC_ADOBE $U_M1

# 7 Unauthorized Users
checkout_license $LIC_ADOBE $U_S1
checkout_license $LIC_ADOBE $U_S2
checkout_license $LIC_ADOBE $U_S3
checkout_license $LIC_ADOBE $U_F1
checkout_license $LIC_ADOBE $U_F2
checkout_license $LIC_ADOBE $U_H1
checkout_license $LIC_ADOBE $U_H2

echo "Checking out MS365 seats..."
checkout_license $LIC_MS365 $U_C1
checkout_license $LIC_MS365 $U_S1
checkout_license $LIC_MS365 $U_F1
checkout_license $LIC_MS365 $U_H1

sleep 2

# Record baseline for MS365 to verify it remains untouched
snipeit_db_query "SELECT assigned_to FROM license_seats WHERE license_id=$LIC_MS365 AND assigned_to IS NOT NULL ORDER BY assigned_to" > /tmp/ms365_baseline.txt

# Setup browser
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/licenses"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="