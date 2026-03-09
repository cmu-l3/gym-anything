#!/bin/bash
echo "=== Exporting search_security_events result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check if a search was executed by looking at recent search jobs
echo "Checking search history..."
SEARCH_JOBS_TEMP=$(mktemp /tmp/search_jobs.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs?output_mode=json&count=50&sort_key=dispatch_time&sort_dir=desc" \
    > "$SEARCH_JOBS_TEMP" 2>/dev/null

# Parse search job results using temp file
# STRICT: Must match verifier requirements exactly
# - Must have "security_logs" index (not just "security")
# - Must have "failed" keyword
SEARCH_ANALYSIS=$(python3 - "$SEARCH_JOBS_TEMP" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    found_security_search = False
    search_query = ""
    result_count = 0
    event_count = 0
    search_status = ""
    job_sid = ""

    for entry in entries:
        content = entry.get('content', {})
        search = content.get('search', '').lower()

        # STRICT: Must have "security_logs" index reference (exact match)
        has_security_logs_index = 'security_logs' in search

        # STRICT: Must have "failed" keyword
        has_failed_keyword = 'failed' in search

        # Both conditions must be met to match
        if has_security_logs_index and has_failed_keyword:
            found_security_search = True
            search_query = content.get('search', '')
            result_count = int(content.get('resultCount', 0))
            event_count = int(content.get('eventCount', 0))
            search_status = content.get('dispatchState', '')
            job_sid = content.get('sid', entry.get('name', ''))
            break

    result = {
        "found_security_search": found_security_search,
        "search_query": search_query,
        "result_count": result_count,
        "event_count": event_count,
        "search_status": search_status,
        "job_sid": job_sid,
        "total_recent_jobs": len(entries)
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        "found_security_search": False,
        "search_query": "",
        "result_count": 0,
        "event_count": 0,
        "search_status": "error",
        "job_sid": "",
        "total_recent_jobs": 0,
        "error": str(e)
    }))
PYEOF
)
rm -f "$SEARCH_JOBS_TEMP"

# Get initial values
INITIAL_JOB_COUNT=$(cat /tmp/initial_job_count 2>/dev/null || echo "0")
INITIAL_SEC_COUNT=$(cat /tmp/initial_sec_event_count 2>/dev/null || echo "0")

# Check current job count
CURRENT_JOB_COUNT_TEMP=$(mktemp /tmp/job_count.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs?output_mode=json&count=0" \
    > "$CURRENT_JOB_COUNT_TEMP" 2>/dev/null
CURRENT_JOB_COUNT=$(python3 -c "
import json
try:
    with open('$CURRENT_JOB_COUNT_TEMP', 'r') as f:
        data = json.load(f)
    print(len(data.get('entry', [])))
except:
    print(0)
" 2>/dev/null)
rm -f "$CURRENT_JOB_COUNT_TEMP"

# Determine if new jobs were created
NEW_JOBS=$((CURRENT_JOB_COUNT - INITIAL_JOB_COUNT))
if [ "$NEW_JOBS" -lt 0 ]; then
    NEW_JOBS=0
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "search_analysis": ${SEARCH_ANALYSIS},
    "initial_job_count": ${INITIAL_JOB_COUNT},
    "current_job_count": ${CURRENT_JOB_COUNT},
    "new_jobs_created": ${NEW_JOBS},
    "initial_security_event_count": ${INITIAL_SEC_COUNT},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
