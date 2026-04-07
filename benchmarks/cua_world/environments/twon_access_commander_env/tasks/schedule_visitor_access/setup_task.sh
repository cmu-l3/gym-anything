#!/bin/bash
echo "=== Setting up schedule_visitor_access task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for 2N Access Commander to be ready
wait_for_ac_demo
ac_login

# 1. Ensure clean state: Delete any existing visitor/user named "Elias Vance"
echo "Cleaning up any existing test data..."
# Check regular users
EXISTING_USERS=$(ac_api GET "/users" | jq -r '.[]? | select(.firstName=="Elias" and .lastName=="Vance") | .id' 2>/dev/null)
for uid in $EXISTING_USERS; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior user Elias Vance" || true
done

# Check visitors (if endpoint exists/differs)
EXISTING_VISITORS=$(ac_api GET "/visitors" 2>/dev/null | jq -r '.visitors[]? // .[]? | select(.firstName=="Elias" and .lastName=="Vance") | .id' 2>/dev/null)
for vid in $EXISTING_VISITORS; do
    ac_api DELETE "/visitors/$vid" > /dev/null 2>&1 && echo "Deleted prior visitor Elias Vance" || true
done

# 2. Get Sandra Okafor's internal ID so the verifier can ensure she was linked as host
SANDRA_ID=$(ac_api GET "/users" | jq -r '.[]? | select(.firstName=="Sandra" and .lastName=="Okafor") | .id' 2>/dev/null | head -1)
echo "$SANDRA_ID" > /tmp/sandra_id.txt
echo "Host ID (Sandra Okafor): $SANDRA_ID"

# 3. Launch Firefox to the dashboard
echo "Launching Firefox..."
launch_firefox_to "${AC_URL}/" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="