#!/bin/bash
echo "=== Setting up correct_inverted_names task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for application to be available
wait_for_ac_demo
ac_login

echo "Inverting names for the target users to simulate the mapping error..."
USERS_JSON=$(ac_api GET "/users")

invert_name() {
    local email="$1"
    local new_first="$2"
    local new_last="$3"
    
    local uid=$(echo "$USERS_JSON" | jq -r ".[] | select(.email==\"$email\") | .id" 2>/dev/null)
    
    if [ -n "$uid" ] && [ "$uid" != "null" ]; then
        local user_record=$(ac_api GET "/users/$uid")
        local modified_record=$(echo "$user_record" | jq -c ".firstName=\"$new_first\" | .lastName=\"$new_last\"")
        
        # Send update to explicitly map names backwards
        local status=$(curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            -X PUT \
            -H "Content-Type: application/json" \
            -w "%{http_code}" \
            -o /dev/null \
            -d "$modified_record" \
            "${AC_URL}/api/v3/users/$uid")
            
        echo "Inverted $email (UID: $uid) - HTTP $status"
    else
        echo "WARNING: Could not find user with email $email"
    fi
}

# Apply the inversion bug to the initial data state
invert_name "s.okafor@buildingtech.com" "Okafor" "Sandra"
invert_name "m.webb@buildingtech.com" "Webb" "Marcus"
invert_name "m.zhang@buildingtech.com" "Zhang" "Mei-Ling"

# Allow a moment for the DB to register the updates
sleep 2

# Record initial user count for anti-gaming (prevent delete & recreate)
UPDATED_USERS=$(ac_api GET "/users")
INITIAL_COUNT=$(echo "$UPDATED_USERS" | jq '. | length' 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_COUNT"

# Launch Firefox directly to the Users page
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="