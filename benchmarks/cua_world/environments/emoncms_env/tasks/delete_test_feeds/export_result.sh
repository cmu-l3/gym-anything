#!/bin/bash
# export_result.sh — Export verification data for delete_test_feeds task

source /workspace/scripts/task_utils.sh

echo "=== Exporting delete_test_feeds results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 1. Check status of Test Feeds (should be deleted)
# -----------------------------------------------------------------------
TEST_FEEDS=("test_voltage_check" "test_ct_sensor_1" "test_calibration_run" "test_mqtt_connection")
TEST_STATUS_JSON=""

for FEED_NAME in "${TEST_FEEDS[@]}"; do
    COUNT=$(db_query "SELECT COUNT(*) FROM feeds WHERE name='${FEED_NAME}'" | head -1)
    if [ -n "$TEST_STATUS_JSON" ]; then
        TEST_STATUS_JSON="${TEST_STATUS_JSON}, "
    fi
    # If count is 0, it is deleted (true)
    IS_DELETED="false"
    if [ "$COUNT" = "0" ]; then
        IS_DELETED="true"
    fi
    TEST_STATUS_JSON="${TEST_STATUS_JSON}\"${FEED_NAME}\": $IS_DELETED"
done

# -----------------------------------------------------------------------
# 2. Check status of Production Feeds (should be intact)
# -----------------------------------------------------------------------
PROD_FEEDS_INTACT="true"
MISSING_PROD_FEEDS=""
TOTAL_PROD_CHECKED=0

if [ -f /tmp/production_feed_ids.txt ]; then
    while read -r FEED_ID; do
        [ -z "$FEED_ID" ] && continue
        TOTAL_PROD_CHECKED=$((TOTAL_PROD_CHECKED + 1))
        
        EXISTS=$(db_query "SELECT COUNT(*) FROM feeds WHERE id=${FEED_ID}" | head -1)
        if [ "$EXISTS" != "1" ]; then
            PROD_FEEDS_INTACT="false"
            MISSING_PROD_FEEDS="${MISSING_PROD_FEEDS}${FEED_ID},"
        fi
    done < /tmp/production_feed_ids.txt
else
    # Fallback if file missing
    PROD_FEEDS_INTACT="false"
fi

# -----------------------------------------------------------------------
# 3. Check Counts
# -----------------------------------------------------------------------
INITIAL_COUNT=$(cat /tmp/initial_feed_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(db_query "SELECT COUNT(*) FROM feeds" | head -1)

# -----------------------------------------------------------------------
# 4. Construct JSON Result
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "test_feeds_status": { ${TEST_STATUS_JSON} },
    "production_feeds_intact": ${PROD_FEEDS_INTACT},
    "missing_production_ids": "${MISSING_PROD_FEEDS}",
    "initial_count": ${INITIAL_COUNT},
    "final_count": ${FINAL_COUNT},
    "total_prod_checked": ${TOTAL_PROD_CHECKED},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="