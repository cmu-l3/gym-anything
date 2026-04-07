#!/bin/bash
set -e
echo "=== Setting up enable_compliance_archival task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

echo "Ensuring Wazuh manager container is running..."
if ! docker ps | grep -q "${CONTAINER}"; then
    echo "Starting Wazuh services..."
    docker compose -f /home/ga/wazuh/docker-compose.yml up -d
    sleep 30
fi

# 1. Reset configuration to baseline (disable logall/logall_json)
echo "Resetting ossec.conf to baseline..."
# Disable logall and logall_json
docker exec "${CONTAINER}" sed -i 's/<logall>yes<\/logall>/<logall>no<\/logall>/g' /var/ossec/etc/ossec.conf
docker exec "${CONTAINER}" sed -i 's/<logall_json>yes<\/logall_json>/<logall_json>no<\/logall_json>/g' /var/ossec/etc/ossec.conf

# Remove the specific localfile block if it exists (using a rough sed deletion or just leaving it clean)
# We'll use a python script inside the container to cleaner remove specific blocks if needed,
# but for simplicity, we assume the baseline doesn't have this custom file.
# We will just ensure the file doesn't exist in the container.

echo "Cleaning up custom log file in container..."
docker exec "${CONTAINER}" rm -f /var/log/legacy_fin_app.log

# Remove any previous proof file
rm -f /home/ga/archive_proof.json

# Restart manager to apply baseline
echo "Restarting Wazuh manager to apply baseline..."
docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control restart > /dev/null 2>&1
sleep 10

# Ensure Firefox is ready (agent usually works in dashboard)
echo "Preparing Firefox..."
ensure_firefox_wazuh "${WAZUH_URL_CONFIG}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="