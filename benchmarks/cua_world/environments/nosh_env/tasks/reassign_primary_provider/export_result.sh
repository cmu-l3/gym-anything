#!/bin/bash
echo "=== Exporting Reassign Provider Results ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Final State
# We want to know which providers are linked to the patient now
# Expected: ID 2 (Carter) should be present. ID 1 (Admin) might be gone or secondary.
# Getting raw JSON output from mysql is tricky, so we'll format it manually or use python in verifier.
# Here we just dump the rows.

echo "Querying database for PID $PID relations..."

# Get list of provider IDs linked to this patient
LINKED_IDS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT id FROM demographics_relate WHERE pid = $PID;")

# Check specifically for Target (2) and Old (1)
HAS_TARGET=$(echo "$LINKED_IDS" | grep -w "2" > /dev/null && echo "true" || echo "false")
HAS_OLD=$(echo "$LINKED_IDS" | grep -w "1" > /dev/null && echo "true" || echo "false")

echo "Linked Provider IDs: $(echo "$LINKED_IDS" | tr '\n' ' ')"

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "target_pid": $PID,
    "linked_provider_ids": [$(echo "$LINKED_IDS" | sed '/^$/d' | paste -sd, -)],
    "has_target_provider": $HAS_TARGET,
    "has_old_provider": $HAS_OLD,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="