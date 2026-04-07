#!/bin/bash
set -e
echo "=== Setting up Detect Web Directory Enumeration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Ensure Nginx is NOT installed initially
echo "Ensuring clean state (removing nginx if present)..."
docker exec "${CONTAINER}" bash -c "dpkg -s nginx >/dev/null 2>&1 && apt-get remove -y --purge nginx nginx-common || true"
docker exec "${CONTAINER}" rm -rf /var/log/nginx 2>/dev/null || true

# 2. Ensure clean ossec.conf (remove nginx config if present from previous runs)
echo "Cleaning ossec.conf..."
docker exec "${CONTAINER}" sed -i '/nginx-access/d' /var/ossec/etc/ossec.conf 2>/dev/null || true
docker exec "${CONTAINER}" sed -i '/\/var\/log\/nginx\/access.log/d' /var/ossec/etc/ossec.conf 2>/dev/null || true

# 3. Ensure clean local_rules.xml
echo "Cleaning local_rules.xml..."
docker exec "${CONTAINER}" sed -i '/id="100500"/d' /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true

# 4. Restart Manager to ensure clean state loaded
echo "Restarting Wazuh Manager..."
docker restart "${CONTAINER}"
sleep 15

# 5. Open Firefox to Dashboard (helpful context, though task is largely terminal/config based)
echo "Opening Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="