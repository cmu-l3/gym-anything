#!/bin/bash
set -e
echo "=== Exporting configure_holiday_list result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# =====================================================
# EXTRACT DATA FROM POSTGRESQL DB
# =====================================================

# 1. Check if the Holiday List exists
# Try standard table names for SDP
LIST_NAME="US Corporate Holidays 2025"
LIST_FOUND="false"
LIST_ID=""

# Query for list existence
# Note: SDP tables are usually lowercase in Postgres, but we try robust querying
DB_LIST_QUERY="SELECT name FROM holidaylist WHERE LOWER(name) LIKE LOWER('%$LIST_NAME%') LIMIT 1;"
LIST_RESULT=$(sdp_db_exec "$DB_LIST_QUERY" 2>/dev/null || echo "")

if [ -n "$LIST_RESULT" ]; then
    LIST_FOUND="true"
    # Get the ID to find associated holidays
    LIST_ID=$(sdp_db_exec "SELECT holidaylistid FROM holidaylist WHERE LOWER(name) LIKE LOWER('%$LIST_NAME%') LIMIT 1;" 2>/dev/null)
fi

# 2. Check for the holidays
# We look for holidays either linked to the list (if we found it) or just by date/name in the system
# created after task start (anti-gaming)

HOLIDAYS_FOUND_JSON="[]"

# Helper to query holidays
# Expects: 2025-01-01 format
check_holiday_date() {
    local target_date="$1"
    # Convert to epoch for some SDP versions, or string for others
    # SDP often stores dates as BIGINT milliseconds
    
    # Try finding by string date match first
    local count=$(sdp_db_exec "SELECT COUNT(*) FROM holidaydetails WHERE TO_CHAR(holidaydate, 'YYYY-MM-DD') = '$target_date' OR holidaydate::text LIKE '%$target_date%';" 2>/dev/null || echo "0")
    
    if [ "$count" = "0" ] || [ -z "$count" ]; then
        # Try finding by epoch range (target date +/- 12 hours)
        local target_epoch=$(date -d "$target_date" +%s)000
        local start_epoch=$((target_epoch - 43200000))
        local end_epoch=$((target_epoch + 43200000))
        count=$(sdp_db_exec "SELECT COUNT(*) FROM holidaydetails WHERE holidaydate BETWEEN $start_epoch AND $end_epoch;" 2>/dev/null || echo "0")
    fi
    
    # Fallback: check 'holidays' or 'holiday' table if 'holidaydetails' fails
    if [ "$count" = "0" ] || [ -z "$count" ]; then
         count=$(sdp_db_exec "SELECT COUNT(*) FROM holidays WHERE TO_CHAR(holiday_date, 'YYYY-MM-DD') = '$target_date';" 2>/dev/null || echo "0")
    fi
    
    echo "$count"
}

# Construct found holidays list
FOUND_COUNT=0
declare -a TARGET_DATES=("2025-01-01" "2025-01-20" "2025-02-17" "2025-05-26" "2025-07-04" "2025-09-01" "2025-11-27" "2025-12-25")
declare -a TARGET_NAMES=("New Year" "Martin Luther" "Presidents" "Memorial" "Independence" "Labor" "Thanksgiving" "Christmas")

HOLIDAYS_JSON_PARTS=""

for i in "${!TARGET_DATES[@]}"; do
    d="${TARGET_DATES[$i]}"
    n="${TARGET_NAMES[$i]}"
    
    # Check if this specific holiday exists
    count=$(check_holiday_date "$d")
    count=$(echo "$count" | tr -d '[:space:]')
    
    if [ "$count" -gt 0 ]; then
        if [ -n "$HOLIDAYS_JSON_PARTS" ]; then HOLIDAYS_JSON_PARTS="$HOLIDAYS_JSON_PARTS,"; fi
        HOLIDAYS_JSON_PARTS="$HOLIDAYS_JSON_PARTS {\"date\": \"$d\", \"found\": true}"
        FOUND_COUNT=$((FOUND_COUNT + 1))
    else
        if [ -n "$HOLIDAYS_JSON_PARTS" ]; then HOLIDAYS_JSON_PARTS="$HOLIDAYS_JSON_PARTS,"; fi
        HOLIDAYS_JSON_PARTS="$HOLIDAYS_JSON_PARTS {\"date\": \"$d\", \"found\": false}"
    fi
done

HOLIDAYS_FOUND_JSON="[$HOLIDAYS_JSON_PARTS]"

# 3. Check for Anti-Gaming (Total Counts)
INITIAL_LIST_COUNT=$(cat /tmp/initial_holiday_list_count.txt 2>/dev/null || echo "0")
CURRENT_LIST_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM holidaylist;" 2>/dev/null || \
    sdp_db_exec "SELECT COUNT(*) FROM holiday_list;" 2>/dev/null || echo "0")
LIST_COUNT_DIFF=$((CURRENT_LIST_COUNT - INITIAL_LIST_COUNT))

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "list_found": $LIST_FOUND,
    "list_name_match": "$LIST_RESULT",
    "holidays_found_count": $FOUND_COUNT,
    "holidays_details": $HOLIDAYS_FOUND_JSON,
    "list_count_diff": $LIST_COUNT_DIFF,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="