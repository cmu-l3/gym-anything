#!/bin/bash
echo "=== Exporting scripted_input_pipeline result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Identify the script created by the agent
ls -1 /opt/splunk/etc/apps/search/bin/ > /tmp/current_bin_files.txt
NEW_SCRIPT=$(comm -13 <(sort /tmp/baseline_bin_files.txt) <(sort /tmp/current_bin_files.txt) | grep -vE "\.pyc|\.pyo" | head -1)

SCRIPT_PATH=""
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT_B64=""

if [ -n "$NEW_SCRIPT" ]; then
    SCRIPT_PATH="/opt/splunk/etc/apps/search/bin/$NEW_SCRIPT"
elif [ -f "/opt/splunk/etc/apps/search/bin/os_metrics_collector.sh" ]; then
    # Fallback if baseline failed
    SCRIPT_PATH="/opt/splunk/etc/apps/search/bin/os_metrics_collector.sh"
elif [ -f "/opt/splunk/etc/apps/search/bin/os_metrics_collector.py" ]; then
    SCRIPT_PATH="/opt/splunk/etc/apps/search/bin/os_metrics_collector.py"
fi

if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "$SCRIPT_PATH" > /tmp/script_path.txt
    if [ -x "$SCRIPT_PATH" ]; then
        echo "true" > /tmp/script_exec.txt
    else
        echo "false" > /tmp/script_exec.txt
    fi
    # Safely extract content to avoid JSON breakage
    cat "$SCRIPT_PATH" | base64 -w 0 > /tmp/script_content.b64
else
    echo "" > /tmp/script_path.txt
    echo "false" > /tmp/script_exec.txt
    echo "" > /tmp/script_content.b64
fi

# 2. Get Scripted Inputs configuration via REST API
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/data/inputs/script?output_mode=json&count=0" \
    > /tmp/inputs_api.json 2>/dev/null

# 3. Wait for data ingestion if input is configured
# Splunk runs scripted inputs based on the interval. If the agent set interval=60,
# it might take up to 60 seconds for the first execution to happen.
if grep -qi "os_telemetry" /tmp/inputs_api.json; then
    echo "Scripted input 'os_telemetry' detected. Waiting 65s for Splunk scheduler to execute and ingest data..."
    sleep 65
else
    echo "No relevant scripted input found. Proceeding immediately."
fi

# 4. Get Saved Search configuration via REST API
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches/Live_Telemetry_Monitor?output_mode=json" \
    > /tmp/search_api.json 2>/dev/null

# 5. Check if events were actually ingested
EVENT_COUNT=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs" \
    -d search="search index=system_logs sourcetype=os_telemetry event_type=live_os_telemetry | stats count" \
    -d exec_mode=oneshot \
    -d output_mode=json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('results',[{}])[0].get('count', '0'))
except:
    print('0')
" 2>/dev/null)
echo "${EVENT_COUNT:-0}" > /tmp/event_count.txt

# 6. Assemble everything into a single JSON securely using Python
PYTHON_JSON_BUILDER=$(cat << 'PYEOF'
import json, sys, os

def read_file(path, default=""):
    try:
        if os.path.exists(path):
            with open(path, 'r') as f:
                return f.read().strip()
    except:
        pass
    return default

try:
    with open('/tmp/inputs_api.json') as f: inputs_data = json.load(f)
except: inputs_data = {}

try:
    with open('/tmp/search_api.json') as f: search_data = json.load(f)
except: search_data = {}

out = {
    "script_path": read_file('/tmp/script_path.txt'),
    "script_executable": read_file('/tmp/script_exec.txt') == "true",
    "script_content_b64": read_file('/tmp/script_content.b64'),
    "inputs_api": inputs_data,
    "search_api": search_data,
    "event_count": int(read_file('/tmp/event_count.txt', "0")),
    "export_timestamp": read_file('/tmp/task_end_timestamp', "0")
}
print(json.dumps(out))
PYEOF
)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "$PYTHON_JSON_BUILDER" > "$TEMP_JSON"

safe_write_json "$TEMP_JSON" /tmp/scripted_input_result.json
echo "Result saved to /tmp/scripted_input_result.json"
echo "=== Export complete ==="