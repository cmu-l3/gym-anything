#!/bin/bash
# Setup for: configure_general_settings task
echo "=== Setting up configure_general_settings task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Verify Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi
echo "Artifactory is accessible."

# 3. Record Initial Configuration (Anti-gaming)
# Fetch current system config to ensure we detect actual changes
echo "Fetching initial system configuration..."
INITIAL_CONFIG=$(curl -s -u admin:password "${ARTIFACTORY_URL}/artifactory/api/system/configuration")

# Extract initial values using Python
python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    # Handle potential empty input
    input_data = sys.stdin.read().strip()
    if not input_data:
        print('Error: Empty config')
        exit(0)
        
    # XML namespacing can be tricky in Artifactory responses, ignore it for simple search
    # or just use string finding if XML parsing fails, but let's try robust parsing
    root = ET.fromstring(input_data)
    
    # Helper to find without namespace
    def find_val(node, tag):
        # iterate all elements
        for elem in node.iter():
            if elem.tag.endswith(tag):
                return elem.text
        return None

    url_base = find_val(root, 'urlBase') or 'None'
    upload_max = find_val(root, 'fileUploadMaxSizeMb') or 'None'
    
    print(f'INITIAL_URL_BASE={url_base}')
    print(f'INITIAL_UPLOAD_MAX={upload_max}')
except Exception as e:
    print(f'Error parsing initial config: {e}')
" <<< "$INITIAL_CONFIG" > /tmp/initial_config_values.txt

cat /tmp/initial_config_values.txt

# 4. Prepare UI
# Ensure Firefox is running and at the Dashboard (forcing agent to navigate to Admin)
echo "Launching Firefox..."
ensure_firefox_running "${ARTIFACTORY_URL}/ui/home"
sleep 5

# Ensure window is maximized and focused
focus_firefox

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="