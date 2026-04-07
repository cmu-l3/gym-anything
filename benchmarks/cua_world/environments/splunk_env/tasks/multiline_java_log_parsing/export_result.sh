#!/bin/bash
echo "=== Exporting multiline_java_log_parsing result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Allow time for any recently added files to be indexed
echo "Waiting 15 seconds to ensure indexing completes..."
sleep 15

# 1. Check if index 'app_logs' exists
INDEX_INFO=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/data/indexes/app_logs?output_mode=json" 2>/dev/null)
INDEX_EXISTS=$(echo "$INDEX_INFO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('true' if 'entry' in d and len(d['entry']) > 0 else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")

# 2. Check if saved search 'Java_Error_Summary' exists
SS_INFO=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches/Java_Error_Summary?output_mode=json" 2>/dev/null)
SS_EXISTS=$(echo "$SS_INFO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('true' if 'entry' in d and len(d['entry']) > 0 else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")

# 3. Check total events in app_logs index
TOTAL_EVENTS=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs" \
    -d search="search index=app_logs | stats count" \
    -d exec_mode=oneshot \
    -d output_mode=json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    if results:
        print(results[0].get('count', '0'))
    else:
        print('0')
except:
    print('0')
" 2>/dev/null || echo "0")

# 4. Check events explicitly matched to java_multiline sourcetype
SOURCETYPE_EVENTS=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs" \
    -d search="search index=app_logs sourcetype=java_multiline | stats count" \
    -d exec_mode=oneshot \
    -d output_mode=json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    if results:
        print(results[0].get('count', '0'))
    else:
        print('0')
except:
    print('0')
" 2>/dev/null || echo "0")

# Format output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "index_exists": $INDEX_EXISTS,
    "saved_search_exists": $SS_EXISTS,
    "total_events": $TOTAL_EVENTS,
    "sourcetype_events": $SOURCETYPE_EVENTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/multiline_result.json

echo "Result saved to /tmp/multiline_result.json"
cat /tmp/multiline_result.json
echo "=== Export complete ==="