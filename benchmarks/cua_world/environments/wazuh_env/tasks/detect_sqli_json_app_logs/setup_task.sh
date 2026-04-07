#!/bin/bash
echo "=== Setting up Detect SQLi Task ==="

source /workspace/scripts/task_utils.sh

CONTAINER="wazuh-wazuh.manager-1"
LOG_DIR="/var/log/custom_webapp"
LOG_FILE="${LOG_DIR}/app.json"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the log directory and file inside the container
echo "Creating mock application logs in container..."
docker exec "${CONTAINER}" mkdir -p "${LOG_DIR}"
docker exec "${CONTAINER}" bash -c "touch ${LOG_FILE}"
docker exec "${CONTAINER}" chmod 666 "${LOG_FILE}"

# 2. Populate with some normal traffic
echo "Seeding normal traffic logs..."
docker exec "${CONTAINER}" bash -c "cat > ${LOG_FILE} <<EOF
{\"timestamp\": \"$(date -Iseconds)\", \"client_ip\": \"192.168.1.10\", \"http_method\": \"GET\", \"http_query\": \"page=home\", \"status\": 200}
{\"timestamp\": \"$(date -Iseconds)\", \"client_ip\": \"192.168.1.12\", \"http_method\": \"POST\", \"http_query\": \"action=login&user=admin\", \"status\": 200}
{\"timestamp\": \"$(date -Iseconds)\", \"client_ip\": \"192.168.1.15\", \"http_method\": \"GET\", \"http_query\": \"id=45\", \"status\": 200}
EOF"

# 3. Ensure clean state for config files (backup if not exists, restore if modified)
echo "Ensuring clean configuration state..."
docker exec "${CONTAINER}" bash -c "cp -n /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak || true"
docker exec "${CONTAINER}" bash -c "cp -n /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml.bak || true"

# Restore original config to ensure no previous task artifacts remain
docker exec "${CONTAINER}" bash -c "cp /var/ossec/etc/ossec.conf.bak /var/ossec/etc/ossec.conf"
docker exec "${CONTAINER}" bash -c "cp /var/ossec/etc/rules/local_rules.xml.bak /var/ossec/etc/rules/local_rules.xml"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/ossec.conf /var/ossec/etc/rules/local_rules.xml
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/ossec.conf /var/ossec/etc/rules/local_rules.xml

# 4. Restart manager to ensure clean state is loaded
echo "Restarting Wazuh manager..."
docker restart "${CONTAINER}"
sleep 10

# 5. Open Firefox to Dashboard
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Log file location (in container): ${LOG_FILE}"