#!/bin/bash
echo "=== Exporting splunk_metrics_pipeline_conversion result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the index details
INDEX_JSON=$(mktemp /tmp/index_data.XXXXXX.json)
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/services/data/indexes/auth_metrics?output_mode=json" > "$INDEX_JSON" 2>/dev/null

# Query the saved search details
SEARCH_JSON=$(mktemp /tmp/search_data.XXXXXX.json)
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/-/-/saved/searches/Auth_Metrics_Rollup?output_mode=json" > "$SEARCH_JSON" 2>/dev/null

# Execute an mstats search to double check if metrics exist (fallback if totalEventCount lags)
MSTATS_JSON=$(mktemp /tmp/mstats_data.XXXXXX.json)
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/services/search/jobs" \
    -d search="| mstats count where index=auth_metrics metric_name=*" \
    -d exec_mode=oneshot \
    -d output_mode=json > "$MSTATS_JSON" 2>/dev/null

# Parse the results
ANALYSIS=$(python3 - "$INDEX_JSON" "$SEARCH_JSON" "$MSTATS_JSON" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        idx_raw = json.load(f)
    if 'entry' in idx_raw and len(idx_raw['entry']) > 0:
        idx_content = idx_raw['entry'][0].get('content', {})
        index_exists = True
        datatype = idx_content.get('datatype', 'unknown')
        total_event_count = int(idx_content.get('totalEventCount', 0))
    else:
        index_exists = False
        datatype = 'none'
        total_event_count = 0
except Exception:
    index_exists = False
    datatype = 'error'
    total_event_count = 0

try:
    with open(sys.argv[2], 'r') as f:
        srch_raw = json.load(f)
    if 'entry' in srch_raw and len(srch_raw['entry']) > 0:
        srch_content = srch_raw['entry'][0].get('content', {})
        search_exists = True
        spl = srch_content.get('search', '')
        is_scheduled = srch_content.get('is_scheduled', False)
        if isinstance(is_scheduled, str):
            is_scheduled = (is_scheduled == '1')
        cron = srch_content.get('cron_schedule', '')
    else:
        search_exists = False
        spl = ''
        is_scheduled = False
        cron = ''
except Exception:
    search_exists = False
    spl = ''
    is_scheduled = False
    cron = ''

try:
    with open(sys.argv[3], 'r') as f:
        mstats_raw = json.load(f)
    results = mstats_raw.get('results', [])
    mstats_count = 0
    if results and len(results) > 0:
        # mstats will return {"count": "X"} if there are data points
        mstats_count = int(results[0].get('count', 0))
except Exception:
    mstats_count = 0

print(json.dumps({
    "index_exists": index_exists,
    "datatype": datatype,
    "total_event_count": total_event_count,
    "mstats_count": mstats_count,
    "search_exists": search_exists,
    "spl": spl,
    "is_scheduled": is_scheduled,
    "cron": cron
}))
PYEOF
)

# Cleanup
rm -f "$INDEX_JSON" "$SEARCH_JSON" "$MSTATS_JSON"

# Create final JSON
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