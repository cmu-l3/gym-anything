#!/bin/bash
# Export script for Aggregate Data CSV Import task

echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# Fallback
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Read Setup Data
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_dv_count 2>/dev/null || echo "0")

# Re-read the CSV to know what UIDs we used (re-parsing the generated file)
CSV_FILE="/home/ga/Documents/pending_import/kailahun_nov2023_data.csv"
DE_UIDS=$(cut -d, -f1 "$CSV_FILE" | tail -n +2 | sort | uniq | tr '\n' ',' | sed "s/,$//;s/,/','/g")
OU_UIDS=$(cut -d, -f3 "$CSV_FILE" | tail -n +2 | sort | uniq | tr '\n' ',' | sed "s/,$//;s/,/','/g")
PERIOD="202311"

# 3. Query Database for Imported Values
echo "Querying database for imported values..."

# Query gets:
# - Current count of matching records
# - Count of records updated/created AFTER task start
DB_STATS=$(dhis2_query "
    SELECT
        COUNT(*) as total_count,
        SUM(CASE WHEN dv.lastupdated >= to_timestamp($TASK_START) THEN 1 ELSE 0 END) as new_count
    FROM datavalue dv
    JOIN dataelement de ON dv.dataelementid = de.dataelementid
    JOIN organisationunit ou ON dv.sourceid = ou.organisationunitid
    JOIN period pe ON dv.periodid = pe.periodid
    WHERE de.uid IN ('$DE_UIDS')
    AND ou.uid IN ('$OU_UIDS')
    AND pe.iso = '$PERIOD'
")

# Parse DB Result (format: total_count | new_count)
CURRENT_COUNT=$(echo "$DB_STATS" | awk -F'|' '{print $1}' | tr -d ' ')
NEWLY_MODIFIED_COUNT=$(echo "$DB_STATS" | awk -F'|' '{print $2}' | tr -d ' ')

# Handle nulls
if [ -z "$CURRENT_COUNT" ]; then CURRENT_COUNT="0"; fi
if [ -z "$NEWLY_MODIFIED_COUNT" ]; then NEWLY_MODIFIED_COUNT="0"; fi

echo "Initial Count: $INITIAL_COUNT"
echo "Current Count: $CURRENT_COUNT"
echo "Newly Modified (Time > Start): $NEWLY_MODIFIED_COUNT"

# 4. Check Agent's Report File
REPORT_FILE="/home/ga/Documents/pending_import/import_result.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 200) # Read first 200 chars
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# 5. Check if Import App was used (Trajectory/VLM check mostly, but we can check if process ran? Hard for web apps)
# We rely on data timestamp verification primarily.

# 6. Create JSON
cat > /tmp/task_result.json << EOF
{
    "initial_db_count": $INITIAL_COUNT,
    "current_db_count": $CURRENT_COUNT,
    "newly_modified_count": $NEWLY_MODIFIED_COUNT,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_created_during_task": $REPORT_CREATED_DURING,
    "report_content_length": $(echo -n "$REPORT_CONTENT" | wc -c),
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Export complete:"
cat /tmp/task_result.json