#!/bin/bash
set -e

echo "=== Exporting Create Lead Filter results ==="

source /workspace/scripts/task_utils.sh

# Task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Database for the Filter
# We look for the filter ID 'SOUTHEAST4'
echo "Querying Vicidial database for filter SOUTHEAST4..."

# We use docker exec to query the DB inside the container
FILTER_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
    SELECT JSON_OBJECT(
        'lead_filter_id', lead_filter_id,
        'lead_filter_name', lead_filter_name,
        'lead_filter_sql', lead_filter_sql,
        'active', active
    ) 
    FROM vicidial_lead_filters 
    WHERE lead_filter_id='SOUTHEAST4' 
    LIMIT 1;
" 2>/dev/null || echo "")

if [ -z "$FILTER_JSON" ]; then
    FILTER_EXISTS="false"
    FILTER_JSON="null"
else
    FILTER_EXISTS="true"
fi

# Get current total count
CURRENT_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_lead_filters;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_filter_count.txt 2>/dev/null || echo "0")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "filter_exists": $FILTER_EXISTS,
    "filter_data": $FILTER_JSON,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="