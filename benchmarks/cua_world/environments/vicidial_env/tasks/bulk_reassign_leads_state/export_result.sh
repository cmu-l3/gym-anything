#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to run SQL
run_sql() {
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$1" 2>/dev/null || echo "0"
}

# 1. Verify Moves (Goal: CA leads in 9002)
# Count CA leads in target list (9002)
CA_IN_TARGET=$(run_sql "SELECT COUNT(*) FROM vicidial_list WHERE list_id='9002' AND state='CA'")

# Count CA leads remaining in source list (9001) - Should be 0
CA_IN_SOURCE=$(run_sql "SELECT COUNT(*) FROM vicidial_list WHERE list_id='9001' AND state='CA'")

# 2. Verify Precision (Goal: Non-CA leads NOT in 9002)
# Count Non-CA leads in target list (9002) - Should be 0
NON_CA_IN_TARGET=$(run_sql "SELECT COUNT(*) FROM vicidial_list WHERE list_id='9002' AND state!='CA'")

# Count Non-CA leads in source list (9001) - Should be remaining
NON_CA_IN_SOURCE=$(run_sql "SELECT COUNT(*) FROM vicidial_list WHERE list_id='9001' AND state!='CA'")

# 3. Verify Timing (Anti-Gaming)
# Check if the records in 9002 were modified AFTER task start
# We check the max modify_date for leads in list 9002
# Unix timestamp conversion might be needed if modify_date is datetime
LATEST_MOD_STR=$(run_sql "SELECT MAX(modify_date) FROM vicidial_list WHERE list_id='9002'")
if [ "$LATEST_MOD_STR" == "NULL" ]; then
    LATEST_MOD_TS=0
else
    # Convert MySQL datetime to unix timestamp
    LATEST_MOD_TS=$(date -d "$LATEST_MOD_STR" +%s)
fi

MODIFIED_DURING_TASK="false"
if [ "$LATEST_MOD_TS" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 4. Total counts for sanity check
TOTAL_LEADS=$(run_sql "SELECT COUNT(*) FROM vicidial_list WHERE list_id IN ('9001', '9002')")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ca_in_target": ${CA_IN_TARGET:-0},
    "ca_in_source": ${CA_IN_SOURCE:-0},
    "non_ca_in_target": ${NON_CA_IN_TARGET:-0},
    "non_ca_in_source": ${NON_CA_IN_SOURCE:-0},
    "total_leads_preserved": ${TOTAL_LEADS:-0},
    "modified_during_task": $MODIFIED_DURING_TASK,
    "latest_modification_ts": $LATEST_MOD_TS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="