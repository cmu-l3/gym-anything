#!/bin/bash
echo "=== Exporting create_incident_report result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Load baselines
INITIAL_REPORT_COUNT=$(cat /tmp/initial_report_count 2>/dev/null || echo "0")
BASELINE_MAX_ID=$(cat /tmp/baseline_max_report_id 2>/dev/null || echo "0")
# Sanitize baseline ID (ensure it's a number)
BASELINE_MAX_ID=$(echo "$BASELINE_MAX_ID" | tr -cd '0-9')
[ -z "$BASELINE_MAX_ID" ] && BASELINE_MAX_ID=0

# Check current count
CURRENT_REPORT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM reports" 2>/dev/null || echo "0")

# Search for the specific report created AFTER the baseline
# We look for the narrative keyword "Dragline 4"
REPORT_QUERY="SELECT id, title, narrative, date FROM reports WHERE id > $BASELINE_MAX_ID AND (narrative LIKE '%Dragline 4%' OR title LIKE '%Dragline 4%') ORDER BY id DESC LIMIT 1"

# NOTE: Column names in 'reports' table might vary slightly (e.g., 'details' vs 'narrative'). 
# We'll try a few variations if the first one returns nothing or errors.
REPORT_DATA=$(opencad_db_query "$REPORT_QUERY" 2>/dev/null)

if [ -z "$REPORT_DATA" ]; then
    # Try alternate column name 'details'
    REPORT_QUERY_ALT="SELECT id, title, details, date FROM reports WHERE id > $BASELINE_MAX_ID AND (details LIKE '%Dragline 4%' OR title LIKE '%Dragline 4%') ORDER BY id DESC LIMIT 1"
    REPORT_DATA=$(opencad_db_query "$REPORT_QUERY_ALT" 2>/dev/null)
fi

REPORT_FOUND="false"
REPORT_ID=""
REPORT_TITLE=""
REPORT_NARRATIVE=""
REPORT_DATE=""

if [ -n "$REPORT_DATA" ]; then
    REPORT_FOUND="true"
    # Parse the tab-separated output
    REPORT_ID=$(echo "$REPORT_DATA" | awk -F'\t' '{print $1}')
    REPORT_TITLE=$(echo "$REPORT_DATA" | awk -F'\t' '{print $2}')
    REPORT_NARRATIVE=$(echo "$REPORT_DATA" | awk -F'\t' '{print $3}')
    REPORT_DATE=$(echo "$REPORT_DATA" | awk -F'\t' '{print $4}')
fi

# Prepare JSON result
# Use python to safely escape strings for JSON to avoid syntax errors
RESULT_JSON=$(python3 -c "
import json
import sys

data = {
    'initial_count': $INITIAL_REPORT_COUNT,
    'current_count': $CURRENT_REPORT_COUNT,
    'baseline_max_id': $BASELINE_MAX_ID,
    'report_found': $REPORT_FOUND,
    'report': {
        'id': '$REPORT_ID',
        'title': '''$REPORT_TITLE''',
        'narrative': '''$REPORT_NARRATIVE''',
        'date': '$REPORT_DATE'
    },
    'timestamp': '$(date -Iseconds)'
}
print(json.dumps(data))
")

safe_write_result "$RESULT_JSON" /tmp/create_incident_report_result.json

echo "Result saved to /tmp/create_incident_report_result.json"
cat /tmp/create_incident_report_result.json
echo "=== Export complete ==="