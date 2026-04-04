#!/bin/bash
echo "=== Setting up Configure Trash Can task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Capture Initial Configuration State (Anti-gaming)
# We query the system configuration to see what the settings are before the agent starts.
# Usually defaults are Enabled=true, Retention=14 days.
echo "Capturing initial system configuration..."
CONFIG_XML=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/system/configuration")

# Parse XML to get initial values using Python
python3 -c "
import sys, xml.etree.ElementTree as ET, json
try:
    tree = ET.fromstring(sys.stdin.read())
    trash_config = tree.find('.//trashCanConfig')
    if trash_config is not None:
        enabled = trash_config.findtext('enabled')
        days = trash_config.findtext('retentionPeriodDays')
        print(json.dumps({'enabled': enabled, 'days': days}))
    else:
        print(json.dumps({'error': 'No trashCanConfig found'}))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" <<< "$CONFIG_XML" > /tmp/initial_config.json

echo "Initial config state:"
cat /tmp/initial_config.json

# 4. Prepare UI
# Start Firefox and navigate to the home page
ensure_firefox_running "${ARTIFACTORY_URL}/ui/"
sleep 5

# Maximize window for visibility
focus_firefox

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="