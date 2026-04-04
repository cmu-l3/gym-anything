#!/bin/bash
echo "=== Exporting create_service_charge result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# Check if app was running
APP_WAS_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# Stop Floreant to release Derby DB lock for querying
kill_floreant
sleep 2

# Verify Database State
echo "Querying database for new service charge..."
mkdir -p /tmp/db_check

# Script to find the record
cat > /tmp/db_check/verify_final.sql << EOF
connect 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
-- List all gratuities to debug
SELECT ID, NAME, PERCENTAGE FROM GRATUITY;
-- Check specifically for our target
SELECT COUNT(*) FROM GRATUITY WHERE UPPER(NAME) LIKE '%LARGE PARTY%';
SELECT PERCENTAGE FROM GRATUITY WHERE UPPER(NAME) LIKE '%LARGE PARTY%';
exit;
EOF

export CLASSPATH="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"
java org.apache.derby.tools.ij /tmp/db_check/verify_final.sql > /tmp/final_db_state.txt 2>&1 || true

# Parse Results
# Check if record exists
RECORD_EXISTS="false"
if grep -q "Large Party" /tmp/final_db_state.txt || grep -q "LARGE PARTY" /tmp/final_db_state.txt; then
    RECORD_EXISTS="true"
fi

# Get Final Count of "Large Party" records (should be >= 1)
# grep the line after the SELECT COUNT query
TARGET_COUNT=$(grep -A 1 "SELECT COUNT(\*) FROM GRATUITY WHERE UPPER(NAME)" /tmp/final_db_state.txt | tail -n 1 | tr -d ' ' | grep -o "[0-9]*" || echo "0")
if [ -z "$TARGET_COUNT" ]; then TARGET_COUNT="0"; fi

# Get the Rate/Percentage
# grep the line after the SELECT PERCENTAGE query.
# Note: Output format is roughly:
# PERCENTAGE
# ----------
# 18.0
#
# We look for the numeric value.
FOUND_RATE=$(grep -A 2 "SELECT PERCENTAGE" /tmp/final_db_state.txt | tail -n 1 | tr -d ' ' || echo "0")

# Compare total counts
INITIAL_TOTAL=$(cat /tmp/initial_gratuity_count.txt 2>/dev/null || echo "0")
# Get final total count
FINAL_TOTAL_QUERY=$(grep -A 1 "SELECT ID, NAME, PERCENTAGE FROM GRATUITY" /tmp/final_db_state.txt | wc -l)
# Approximate check, exact parsing is brittle with ij output, relying on TARGET_COUNT is better

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_WAS_RUNNING,
    "record_exists": $RECORD_EXISTS,
    "target_record_count": $TARGET_COUNT,
    "found_rate": "$FOUND_RATE",
    "initial_total_count": $INITIAL_TOTAL,
    "db_output_log": "/tmp/final_db_state.txt"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Database Output Log:"
cat /tmp/final_db_state.txt
echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export complete ==="