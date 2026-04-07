#!/bin/bash
echo "=== Exporting results for deactivate_patient_record ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TARGET_PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")
INITIAL_ACTIVE_COUNT=$(cat /tmp/initial_active_count.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Final State
echo "Querying database..."

# Get Target Patient Status
TARGET_STATUS_JSON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "SELECT active, firstname, lastname FROM demographics WHERE pid=$TARGET_PID \G" 2>/dev/null)

# Parse the MySQL output (simple grep/awk since it's raw text)
FINAL_ACTIVE=$(echo "$TARGET_STATUS_JSON" | grep "active:" | awk '{print $2}' | tr -d '[:space:]')

# Get Total Active Count
FINAL_ACTIVE_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM demographics WHERE active=1;" 2>/dev/null | tr -d '[:space:]')

# Check for Notes (to verify the "Add a note" requirement)
# Looking for recent messages/notes for this PID
# Note: Table might be 'messages' or 'encounters' or specific note table depending on NOSH schema.
# In NOSH, patient notes often live in 'messaging' or 'encounters'. We'll check 'messaging' for simplicity or general log.
# Let's check 'demographics' for a 'notes' field or similar if available, otherwise skip specific note content check in DB 
# and rely on VLM for that part, as schema reverse engineering is risky.
# However, we can check if *any* data was updated.
LAST_UPDATE_TIME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT UPDATE_TIME FROM information_schema.tables WHERE TABLE_SCHEMA='nosh' AND TABLE_NAME='demographics';" 2>/dev/null)

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_pid": "$TARGET_PID",
    "initial_active_count": $INITIAL_ACTIVE_COUNT,
    "final_active_count": $FINAL_ACTIVE_COUNT,
    "target_final_active_status": "$FINAL_ACTIVE",
    "last_db_update": "$LAST_UPDATE_TIME",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json