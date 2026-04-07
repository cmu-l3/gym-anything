#!/bin/bash
set -e
echo "=== Setting up Configure VirusTotal Integration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Docker is running
systemctl start docker 2>/dev/null || true
sleep 3

# Wait for Wazuh manager to be healthy
echo "Waiting for Wazuh manager..."
wait_for_service "Wazuh Manager" "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status | grep -q 'is running'" 60

# Wait for Wazuh API
echo "Waiting for Wazuh API..."
wait_for_service "Wazuh API" "curl -sk -u '${WAZUH_API_USER}:${WAZUH_API_PASS}' '${WAZUH_API_URL}/' | grep -q 'Wazuh'" 60

# Clean up any existing VirusTotal integration to ensure a fresh start
echo "Cleaning existing configuration..."
docker exec wazuh-wazuh.manager-1 bash -c "
    if grep -q '<name>virustotal</name>' /var/ossec/etc/ossec.conf; then
        # Remove integration block using python for reliability
        python3 -c \"
import re
with open('/var/ossec/etc/ossec.conf', 'r') as f:
    content = f.read()
# Regex to remove integration block with virustotal name
# Handles distinct lines and potential whitespace variations
pattern = r'<integration>\s*<name>virustotal</name>.*?</integration>'
content = re.sub(pattern, '', content, flags=re.DOTALL)
with open('/var/ossec/etc/ossec.conf', 'w') as f:
    f.write(content)
\"
        # Restart to apply cleanup
        /var/ossec/bin/wazuh-control restart
    fi
" 2>/dev/null || echo "Cleanup warning: might have failed to remove existing config, continuing..."

# Wait a moment for restart if it happened
sleep 5

# Record initial state of ossec.conf (MD5 hash)
echo "Recording initial configuration state..."
docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/ossec.conf > /tmp/initial_ossec.conf
md5sum /tmp/initial_ossec.conf | awk '{print $1}' > /tmp/initial_ossec_md5.txt

# Start Firefox on Wazuh dashboard to set the visual context
echo "Starting Firefox..."
ensure_firefox_wazuh "https://localhost/app/wz-home"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="