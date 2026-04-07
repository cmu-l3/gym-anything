#!/bin/bash
echo "=== Setting up license_seat_checkout task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# API Helpers
API_TOKEN=$(cat /home/ga/snipeit/api_token.txt 2>/dev/null)

api_post() {
    curl -s -X POST "http://localhost:8000/api/v1/$1" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$2"
}

api_get() {
    curl -s -X GET "http://localhost:8000/api/v1/$1" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Accept: application/json"
}

# 1. Ensure target users exist
ensure_user() {
    local fname=$1
    local lname=$2
    local uname=$3
    local uid=$(snipeit_db_query "SELECT id FROM users WHERE username='$uname' LIMIT 1" | tr -d '[:space:]')
    
    if [ -z "$uid" ]; then
        api_post "users" "{\"first_name\":\"$fname\", \"last_name\":\"$lname\", \"username\":\"$uname\", \"password\":\"password123\", \"password_confirmation\":\"password123\", \"email\":\"$uname@consulting.example.com\", \"activated\":true}" > /dev/null
        uid=$(snipeit_db_query "SELECT id FROM users WHERE username='$uname' LIMIT 1" | tr -d '[:space:]')
    fi
    echo "Ensured user $uname (ID: $uid)"
}

echo "--- Preparing users ---"
ensure_user "Sarah" "Chen" "schen"
ensure_user "Marcus" "Williams" "mwilliams"
ensure_user "Priya" "Patel" "ppatel"
ensure_user "James" "O'Brien" "jobrien"
ensure_user "Lisa" "Nakamura" "lnakamura"

# 2. Ensure software license category exists
echo "--- Preparing categories ---"
CAT_ID=$(api_get "categories?category_type=license" | jq -r '.rows[0].id // empty')
if [ -z "$CAT_ID" ]; then
    CAT_ID=$(api_post "categories" '{"name":"Software Licenses","category_type":"license"}' | jq -r '.payload.id // .id // empty')
fi
if [ -z "$CAT_ID" ] || [ "$CAT_ID" == "null" ]; then
    CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE category_type='license' LIMIT 1" | tr -d '[:space:]')
fi
echo "Using license category ID: $CAT_ID"

# 3. Clean and recreate licenses to ensure correct seat counts
echo "--- Preparing licenses ---"
# Safely clear old ones
snipeit_db_query "DELETE FROM license_seats WHERE license_id IN (SELECT id FROM licenses WHERE name IN ('Microsoft 365 E3', 'Adobe Creative Cloud', 'Slack Business'))"
snipeit_db_query "DELETE FROM licenses WHERE name IN ('Microsoft 365 E3', 'Adobe Creative Cloud', 'Slack Business')"

# Create them fresh via API to auto-generate seats
LIC_MS365=$(api_post "licenses" "{\"name\":\"Microsoft 365 E3\",\"seats\":15,\"category_id\":$CAT_ID}" | jq -r '.payload.id // .id // empty')
LIC_ADOBE=$(api_post "licenses" "{\"name\":\"Adobe Creative Cloud\",\"seats\":10,\"category_id\":$CAT_ID}" | jq -r '.payload.id // .id // empty')
LIC_SLACK=$(api_post "licenses" "{\"name\":\"Slack Business\",\"seats\":20,\"category_id\":$CAT_ID}" | jq -r '.payload.id // .id // empty')

echo "Licenses created: MS365 ($LIC_MS365), Adobe ($LIC_ADOBE), Slack ($LIC_SLACK)"

# 4. Check out some pre-existing seats (to test C5: don't touch existing)
echo "--- Pre-assigning some seats ---"
ADMIN_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='admin' LIMIT 1" | tr -d '[:space:]')
if [ -n "$LIC_MS365" ] && [ "$LIC_MS365" != "null" ]; then
    api_post "licenses/${LIC_MS365}/checkout" "{\"assigned_to\":$ADMIN_ID}" > /dev/null
fi
if [ -n "$LIC_ADOBE" ] && [ "$LIC_ADOBE" != "null" ]; then
    api_post "licenses/${LIC_ADOBE}/checkout" "{\"assigned_to\":$ADMIN_ID}" > /dev/null
fi

# 5. Snapshot pre-existing seat assignments
echo "--- Recording initial state ---"
snipeit_db_query "SELECT id, license_id, assigned_to FROM license_seats WHERE assigned_to IS NOT NULL" > /tmp/pre_existing_seats.txt
echo "Pre-existing seats count: $(wc -l < /tmp/pre_existing_seats.txt)"

# 6. Open UI for agent
echo "--- Launching browser ---"
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/licenses"
sleep 3
take_screenshot /tmp/license_checkout_initial.png

echo "=== Setup complete ==="