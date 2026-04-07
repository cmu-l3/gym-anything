#!/bin/bash
echo "=== Setting up classify_ssh_events task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline state for anti-gaming (to ensure objects are created during the task)
echo "Recording baseline state..."
INITIAL_STATE=$(python3 - << 'PYEOF'
import sys, json, subprocess

def get_names(endpoint):
    try:
        res = subprocess.run(
            ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', f'https://localhost:8089{endpoint}?output_mode=json&count=0'],
            capture_output=True, text=True
        )
        data = json.loads(res.stdout)
        return [e.get('name') for e in data.get('entry', [])]
    except Exception as e:
        return []

eventtypes = get_names('/servicesNS/-/-/saved/eventtypes')
searches = get_names('/servicesNS/-/-/saved/searches')

print(json.dumps({
    "eventtypes": eventtypes,
    "searches": searches
}))
PYEOF
)
echo "$INITIAL_STATE" > /tmp/classify_ssh_initial.json
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="