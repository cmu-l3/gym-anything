#!/bin/bash
set -e
echo "=== Setting up Configure Command Wodle task ==="

source /workspace/scripts/task_utils.sh

# Define variables
CONTAINER="wazuh-wazuh.manager-1"
CONFIG_FILE="/var/ossec/etc/ossec.conf"
HOST_BACKUP="/tmp/ossec_original.conf"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Ensure clean state: Remove any existing command wodles from ossec.conf
# We use a python script inside the container to strip existing wodles to ensure valid XML
echo "Sanitizing ossec.conf..."
docker cp "${CONTAINER}:${CONFIG_FILE}" "${HOST_BACKUP}"

# Sanitize using python on host then copy back (easier than installing tools in container)
python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('${HOST_BACKUP}')
    root = tree.getroot()
    # Remove existing command wodles
    for wodle in root.findall(\"wodle[@name='command']\"):
        root.remove(wodle)
    tree.write('${HOST_BACKUP}')
    print('Sanitization complete')
except Exception as e:
    print(f'Error sanitizing XML: {e}')
"

# Copy sanitized config back and set permissions
docker cp "${HOST_BACKUP}" "${CONTAINER}:${CONFIG_FILE}"
docker exec -u root "${CONTAINER}" chown root:wazuh "${CONFIG_FILE}"
docker exec -u root "${CONTAINER}" chmod 660 "${CONFIG_FILE}"

# Calculate initial checksum for change detection
md5sum "${HOST_BACKUP}" | awk '{print $1}' > /tmp/initial_config_md5.txt

# 2. Restart manager to ensure it's running with clean config
echo "Restarting Wazuh manager..."
docker restart "${CONTAINER}"
sleep 10

# 3. Wait for API to be ready
echo "Waiting for Wazuh API..."
for i in {1..30}; do
    if check_api_health; then
        echo "API is ready."
        break
    fi
    sleep 2
done

# 4. Open Firefox to Dashboard (provides a visual interface for the agent)
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="