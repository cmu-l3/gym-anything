#!/bin/bash
echo "=== Exporting add_data_source result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current monitor inputs
echo "Checking monitor inputs..."
MONITORS_TEMP=$(mktemp /tmp/monitors.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/data/inputs/monitor?output_mode=json&count=0" \
    > "$MONITORS_TEMP" 2>/dev/null

# Analyze monitor inputs
# STRICT: Must match verifier requirements exactly
# - Path must be exactly "/var/log/kern.log"
# - Index must be "system_logs" (not "main")
MONITOR_ANALYSIS=$(python3 - "$MONITORS_TEMP" << 'PYEOF'
import sys, json

# STRICT: Expected path
EXPECTED_PATH = "/var/log/kern.log"
EXPECTED_INDEX = "system_logs"

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    # Load initial monitors
    try:
        with open('/tmp/initial_monitors.json', 'r') as f:
            initial_paths = json.loads(f.read())
    except:
        initial_paths = []

    found_kern_monitor = False
    monitor_path = ""
    monitor_index = ""
    monitor_sourcetype = ""
    all_current_paths = []
    new_monitors = []

    for entry in entries:
        name = entry.get('name', '')
        all_current_paths.append(name)
        content = entry.get('content', {})

        if name not in initial_paths:
            new_monitors.append(name)

        # STRICT: Check for exact path match "/var/log/kern.log"
        # The name in Splunk API is the path
        if name == EXPECTED_PATH:
            found_kern_monitor = True
            monitor_path = name
            monitor_index = content.get('index', '')
            monitor_sourcetype = content.get('sourcetype', '')
            break

    # If exact path not found, check new monitors and report
    # (verifier will still fail if path is wrong)
    if not found_kern_monitor and new_monitors:
        for entry in entries:
            name = entry.get('name', '')
            if name in new_monitors:
                content = entry.get('content', {})
                # Report it but note it's not the exact path
                found_kern_monitor = ('kern' in name.lower())
                monitor_path = name
                monitor_index = content.get('index', '')
                monitor_sourcetype = content.get('sourcetype', '')
                break

    result = {
        "found_kern_monitor": found_kern_monitor,
        "monitor_path": monitor_path,
        "monitor_index": monitor_index,
        "monitor_sourcetype": monitor_sourcetype,
        "new_monitors": new_monitors,
        "total_monitors": len(all_current_paths)
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        "found_kern_monitor": False,
        "monitor_path": "",
        "monitor_index": "",
        "monitor_sourcetype": "",
        "new_monitors": [],
        "total_monitors": 0,
        "error": str(e)
    }))
PYEOF
)
rm -f "$MONITORS_TEMP"

# Also check inputs.conf directly for the monitor (fallback detection)
INPUTS_CONF_CHECK="false"
if grep -q "/var/log/kern.log" /opt/splunk/etc/system/local/inputs.conf 2>/dev/null || \
   grep -rq "/var/log/kern.log" /opt/splunk/etc/apps/*/local/inputs.conf 2>/dev/null || \
   grep -rq "/var/log/kern.log" /opt/splunk/etc/users/*/search/local/inputs.conf 2>/dev/null; then
    INPUTS_CONF_CHECK="true"
fi

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_monitor_count 2>/dev/null || echo "0")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "monitor_analysis": ${MONITOR_ANALYSIS},
    "inputs_conf_has_kern": ${INPUTS_CONF_CHECK},
    "initial_monitor_count": ${INITIAL_COUNT},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
