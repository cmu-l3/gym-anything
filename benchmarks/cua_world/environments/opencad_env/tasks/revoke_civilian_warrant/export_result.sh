#!/bin/bash
echo "=== Exporting Revoke Civilian Warrant result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load ID data saved during setup
CIV_ID=$(grep -oP '"civilian_id": "\K[^"]+' /tmp/task_ids.json)
WARRANT_ID=$(grep -oP '"warrant_id": "\K[^"]+' /tmp/task_ids.json)
CIV_NAME="Marcus Vance"
WARRANT_REASON="Failure to Appear"

echo "Checking status for Civilian ID: $CIV_ID and Warrant ID: $WARRANT_ID"

# 1. Check if the specific warrant still exists
# If count is 0, it means it was deleted (Success)
WARRANT_EXISTS_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_warrants WHERE id=$WARRANT_ID")
if [ "$WARRANT_EXISTS_COUNT" -eq "0" ]; then
    WARRANT_REMOVED="true"
else
    WARRANT_REMOVED="false"
fi

# 2. Check if civilian still exists (Safety check)
CIV_EXISTS_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_names WHERE id=$CIV_ID")
if [ "$CIV_EXISTS_COUNT" -eq "1" ]; then
    CIV_PRESERVED="true"
else
    CIV_PRESERVED="false"
fi

# 3. Check total warrant counts (Anti-gaming: ensure they didn't wipe table)
INITIAL_COUNT=$(cat /tmp/initial_warrant_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_warrants")
COUNT_DIFF=$((INITIAL_COUNT - FINAL_COUNT))

# 4. Check login status (for partial credit/context)
# Simple check if session cookie exists or url is not login
LOGGED_IN="false"
# We can't easily check PHP session from bash, but we can assume interaction implies login if verification passes.
# We'll rely on VLM for login verification.

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "target_warrant_id": "$WARRANT_ID",
    "target_civilian_id": "$CIV_ID",
    "warrant_removed": $WARRANT_REMOVED,
    "civilian_preserved": $CIV_PRESERVED,
    "initial_warrant_count": $INITIAL_COUNT,
    "final_warrant_count": $FINAL_COUNT,
    "count_difference": $COUNT_DIFF,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/revoke_warrant_result.json

echo "Result saved to /tmp/revoke_warrant_result.json"
cat /tmp/revoke_warrant_result.json
echo "=== Export complete ==="