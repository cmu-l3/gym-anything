#!/bin/bash
# Export script for Reactivate Patient Record task

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Read Initial State
if [ -f /tmp/reactivate_initial_state.json ]; then
    TARGET_PID=$(grep -oP '"target_pid": "\K[^"]+' /tmp/reactivate_initial_state.json)
    INITIAL_COUNT=$(grep -oP '"initial_count": \K[0-9]+' /tmp/reactivate_initial_state.json)
else
    echo "Warning: Initial state file missing"
    TARGET_PID=""
    INITIAL_COUNT=0
fi

# 3. Query Current DB State
echo "Querying database..."

# Get status of the specific target PID
if [ -n "$TARGET_PID" ]; then
    CURRENT_STATUS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT active FROM demographics WHERE pid='$TARGET_PID';")
else
    CURRENT_STATUS="unknown"
fi

# Get current total count of "Maria Garcia" records (to detect duplicates)
CURRENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM demographics WHERE firstname='Maria' AND lastname='Garcia';")

# 4. Generate Result JSON
# Use a temp file to avoid permission issues, then move
TEMP_JSON=$(mktemp /tmp/reactivate_result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "target_pid": "$TARGET_PID",
    "final_active_status": "${CURRENT_STATUS:-0}",
    "initial_record_count": $INITIAL_COUNT,
    "final_record_count": $CURRENT_COUNT,
    "timestamp": $(date +%s)
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json