#!/bin/bash
echo "=== Setting up merge_duplicate_users task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure target directory exists and clear old artifacts
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/merge_report.txt 2>/dev/null || true

# Wait for 2N Access Commander to be ready
wait_for_ac_demo
ac_login

echo "Preparing database state..."

# 1. Clean up any previous artifacts from this task
ac_delete_user_by_name "Meiling" "Zhang"

# 2. Check for the primary user (Mei-Ling Zhang) from the seed data
PRIMARY_ID=$(ac_api GET "/users" | jq -r '.[] | select(.email=="m.zhang@buildingtech.com") | .id' 2>/dev/null)

if [ -z "$PRIMARY_ID" ] || [ "$PRIMARY_ID" = "null" ]; then
    echo "WARNING: Primary user not found, recreating..."
    ac_api POST "/users" '{"firstName":"Mei-Ling","lastName":"Zhang","email":"m.zhang@buildingtech.com","company":"BuildingTech Solutions","enabled":true}' > /dev/null
    # Since we can't easily push the exact card payload without knowing AC schema, 
    # the verifier will use string containment matching on the user profile.
fi

# 3. Create the duplicate user (Meiling Zhang)
echo "Creating duplicate user..."
DUP_RESP=$(ac_api POST "/users" '{"firstName":"Meiling","lastName":"Zhang","email":"ml.zhang@buildingtech.com","company":"BuildingTech Solutions","enabled":true}')
DUP_ID=$(echo "$DUP_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)

# Assign the duplicate's card (trying standard schemas, but agent is also told the card number directly)
if [ -n "$DUP_ID" ]; then
    ac_api PUT "/users/$DUP_ID" '{"cards":[{"cardNumber":"0009876543"}]}' > /dev/null 2>&1 || true
    ac_api PUT "/users/$DUP_ID/cards" '{"cardNumber":"0009876543"}' > /dev/null 2>&1 || true
fi

# 4. Record initial counts
ac_api GET "/users" | jq 'length' > /tmp/initial_user_count.txt
ac_api GET "/users" | jq '[.[] | select(.lastName=="Zhang" or .lastName=="zhang")] | length' > /tmp/initial_zhang_count.txt

# 5. Launch Firefox to the Users list
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="