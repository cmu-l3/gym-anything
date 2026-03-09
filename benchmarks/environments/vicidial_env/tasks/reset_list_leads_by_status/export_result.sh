#!/bin/bash
set -e

echo "=== Exporting Reset List Leads Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Database verification queries
# We want to check the status of leads in List 9001
# Specifically, we want to know how many are now 'N' (Not called since reset) for each status type

# 1. Get counts of RESET leads (called_since_last_reset='N') by status
# Output format: STATUS:COUNT (e.g., B:10)
RESET_COUNTS_RAW=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT status, count(*) FROM vicidial_list WHERE list_id='9001' AND called_since_last_reset='N' GROUP BY status;")

# 2. Get counts of NOT RESET leads (called_since_last_reset='Y') for protected statuses
# We expect SALE and DNC to be here.
PROTECTED_COUNTS_RAW=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT status, count(*) FROM vicidial_list WHERE list_id='9001' AND called_since_last_reset='Y' AND status IN ('SALE', 'DNC') GROUP BY status;")

# 3. Check modification times (Anti-gaming)
# Check if any leads were modified AFTER task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert unix timestamp to MySQL datetime format roughly, or just check if any modify_date > FROM_UNIXTIME(TASK_START)
# Note: Vicidial modify_date is TIMESTAMP or DATETIME.
MODIFIED_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT count(*) FROM vicidial_list WHERE list_id='9001' AND modify_date > FROM_UNIXTIME($TASK_START);")

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "reset_counts_raw": "$(echo "$RESET_COUNTS_RAW" | sed ':a;N;$!ba;s/\n/|/g')",
    "protected_counts_raw": "$(echo "$PROTECTED_COUNTS_RAW" | sed ':a;N;$!ba;s/\n/|/g')",
    "modified_leads_count": ${MODIFIED_COUNT:-0},
    "task_start_ts": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result:"
cat /tmp/task_result.json
echo "=== Export complete ==="