#!/bin/bash
echo "=== Exporting configure_shift results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# Stop Floreant to release DB lock for verification
echo "Stopping Floreant POS for verification..."
kill_floreant

# Query Database for the new shift
echo "Querying database for 'Early Bird' shift..."
export CLASSPATH="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"
mkdir -p /tmp/derby_scripts

# Floreant stores time in SHIFT table. 
# Depending on version, it might be START_TIME/END_TIME (long/timestamp) or string.
# We will select relevant columns.
cat > /tmp/derby_scripts/verify_shift.sql <<EOF
connect 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT ID, NAME, START_TIME, END_TIME FROM SHIFT WHERE NAME = 'Early Bird';
exit;
EOF

# Run query and capture output
DB_OUTPUT=$(java -Dderby.system.home=/opt/floreantpos/database/derby-server org.apache.derby.tools.ij /tmp/derby_scripts/verify_shift.sql 2>&1 || echo "DB_ERROR")

echo "DB Output:"
echo "$DB_OUTPUT"

# Parse DB Output for existence and values
SHIFT_EXISTS="false"
START_TIME_MATCH="false"
END_TIME_MATCH="false"

if echo "$DB_OUTPUT" | grep -q "Early Bird"; then
    SHIFT_EXISTS="true"
    
    # Check for times - looking for common representations
    # 05:00 AM might be stored as milliseconds or string
    # 5 * 60 * 60 * 1000 = 18000000
    # 10 * 60 * 60 * 1000 = 36000000
    
    if echo "$DB_OUTPUT" | grep -qE "18000000|05:00|5:00"; then
        START_TIME_MATCH="true"
    fi
    
    if echo "$DB_OUTPUT" | grep -qE "36000000|10:00"; then
        END_TIME_MATCH="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "shift_exists": $SHIFT_EXISTS,
    "start_time_match": $START_TIME_MATCH,
    "end_time_match": $END_TIME_MATCH,
    "db_output_snippet": "$(echo "$DB_OUTPUT" | grep "Early Bird" | head -1 | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json