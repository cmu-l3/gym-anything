#!/bin/bash
echo "=== Setting up soar_webhook_integration task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline saved searches (Alerts) to detect new ones
echo "Recording baseline alerts..."
splunk_list_saved_searches | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    with open('/tmp/soar_initial_alerts.json', 'w') as f:
        json.dump(names, f)
    print(f'Baseline: {len(names)} alerts')
except Exception as e:
    print(f'Error recording alerts: {e}')
    with open('/tmp/soar_initial_alerts.json', 'w') as f:
        json.dump([], f)
" 2>/dev/null

# Record baseline dashboards (Views) to detect new ones
echo "Recording baseline dashboards..."
splunk_list_dashboards | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    with open('/tmp/soar_initial_dashboards.json', 'w') as f:
        json.dump(names, f)
    print(f'Baseline: {len(names)} dashboards')
except Exception as e:
    print(f'Error recording dashboards: {e}')
    with open('/tmp/soar_initial_dashboards.json', 'w') as f:
        json.dump([], f)
" 2>/dev/null

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="