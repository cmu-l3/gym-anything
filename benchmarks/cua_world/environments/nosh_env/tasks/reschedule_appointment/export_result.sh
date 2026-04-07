#!/bin/bash
echo "=== Exporting Reschedule Task Results ==="

# Retrieve the target dates defined in setup
OLD_DATETIME=$(cat /tmp/task_old_datetime.txt)
NEW_DATETIME=$(cat /tmp/task_new_datetime.txt)

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for NEW Slot Status
# We check for an active appointment at the NEW time (+/- 5 mins tolerance)
echo "Checking new slot at $NEW_DATETIME..."
NEW_SLOT_JSON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "
SELECT JSON_OBJECT(
    'count', COUNT(*),
    'reason', COALESCE(MAX(reason), ''),
    'visit_type', COALESCE(MAX(visit_type), ''),
    'status', COALESCE(MAX(status), '')
)
FROM schedule 
WHERE pid = 999 
AND active = 1 
AND status != 'cancelled'
AND start BETWEEN DATE_SUB('${NEW_DATETIME}', INTERVAL 5 MINUTE) AND DATE_ADD('${NEW_DATETIME}', INTERVAL 5 MINUTE);
" 2>/dev/null)

# 3. Query Database for OLD Slot Status
# We check if the OLD slot is empty or cancelled
echo "Checking old slot at $OLD_DATETIME..."
OLD_SLOT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "
SELECT COUNT(*)
FROM schedule 
WHERE pid = 999 
AND active = 1 
AND status != 'cancelled'
AND start BETWEEN DATE_SUB('${OLD_DATETIME}', INTERVAL 5 MINUTE) AND DATE_ADD('${OLD_DATETIME}', INTERVAL 5 MINUTE);
" 2>/dev/null)

# 4. Check for ANY appointments for this patient (debugging/fallback)
TOTAL_APPTS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM schedule WHERE pid = 999 AND active=1;" 2>/dev/null)

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "new_slot": $NEW_SLOT_JSON,
    "old_slot_count": ${OLD_SLOT_COUNT:-0},
    "total_active_appts": ${TOTAL_APPTS:-0},
    "target_datetime": "$NEW_DATETIME",
    "original_datetime": "$OLD_DATETIME",
    "screenshot_path": "/tmp/task_final.png",
    "task_timestamp": $(date +%s)
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="