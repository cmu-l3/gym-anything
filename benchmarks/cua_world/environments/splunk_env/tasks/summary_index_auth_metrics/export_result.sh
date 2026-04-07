#!/bin/bash
echo "=== Exporting summary_index_auth_metrics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get all indexes
INDEXES_TEMP=$(mktemp /tmp/indexes.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/data/indexes?output_mode=json&count=0" \
    > "$INDEXES_TEMP" 2>/dev/null

# 2. Get all saved searches
SEARCHES_TEMP=$(mktemp /tmp/searches.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > "$SEARCHES_TEMP" 2>/dev/null

# 3. Get event count in auth_summary index (oneshot search)
COUNT_TEMP=$(mktemp /tmp/count.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs" \
    -d search="search index=auth_summary | stats count" \
    -d exec_mode=oneshot \
    -d output_mode=json \
    > "$COUNT_TEMP" 2>/dev/null

# Analyze collected data
ANALYSIS=$(python3 - "$INDEXES_TEMP" "$SEARCHES_TEMP" "$COUNT_TEMP" << 'PYEOF'
import sys, json

try:
    # 1. Parse Indexes
    with open(sys.argv[1], 'r') as f:
        indexes_data = json.load(f)
    
    index_exists = False
    for entry in indexes_data.get('entry', []):
        if entry.get('name', '').lower() == 'auth_summary':
            index_exists = True
            break

    # 2. Parse Saved Searches
    with open(sys.argv[2], 'r') as f:
        searches_data = json.load(f)
    
    search_exists = False
    search_spl = ""
    is_scheduled = False
    cron_schedule = ""
    
    for entry in searches_data.get('entry', []):
        if entry.get('name', '').lower() == 'auth_metrics_collector':
            search_exists = True
            content = entry.get('content', {})
            search_spl = content.get('search', '')
            is_scheduled = content.get('is_scheduled', '0') == '1'
            cron_schedule = content.get('cron_schedule', '')
            break

    # 3. Parse Event Count
    event_count = 0
    try:
        with open(sys.argv[3], 'r') as f:
            count_data = json.load(f)
        results = count_data.get('results', [])
        if results:
            event_count = int(results[0].get('count', 0))
    except Exception:
        pass

    result = {
        "index_exists": index_exists,
        "search_exists": search_exists,
        "search_spl": search_spl,
        "is_scheduled": is_scheduled,
        "cron_schedule": cron_schedule,
        "event_count": event_count
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)

rm -f "$INDEXES_TEMP" "$SEARCHES_TEMP" "$COUNT_TEMP"

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="