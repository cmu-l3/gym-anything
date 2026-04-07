#!/bin/bash
# Setup for implement_custom_app_brute_force
set -e

echo "=== Setting up Custom App Brute Force Task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the application log directory and seed file
LOG_DIR="/var/log/finconnect"
LOG_FILE="${LOG_DIR}/app.log"

# Create directory inside the manager container (since it reads the file)
# Note: In this environment, we usually map volumes or exec into container.
# However, for 'localfile' ingestion, the file usually needs to be visible to the manager.
# If the manager is in Docker, we must create the file INSIDE the container or in a mounted volume.
# Based on env.json, /home/ga is mounted. Let's assume the user edits config to point to a file accessible by the manager.
# BUT, standard practice is monitoring /var/log inside the container or mounted host logs.
# We will create the file inside the container to be safe and easiest for the agent to reference as /var/log/...

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

echo "Creating log directory in container..."
docker exec "$CONTAINER" mkdir -p "$LOG_DIR"

# Seed with some normal traffic (non-attacking)
echo "Seeding historical logs..."
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
SEED_DATA="${TIMESTAMP} FinConnect: [Login] User=alice IP=192.168.1.10 Status=Success
${TIMESTAMP} FinConnect: [Login] User=bob IP=192.168.1.11 Status=Success
${TIMESTAMP} FinConnect: [Login] User=charlie IP=192.168.1.12 Status=Failed
${TIMESTAMP} FinConnect: [Login] User=charlie IP=192.168.1.12 Status=Success"

docker exec "$CONTAINER" bash -c "echo \"$SEED_DATA\" > $LOG_FILE"
docker exec "$CONTAINER" chmod 644 "$LOG_FILE"

# 2. Backup original config files to verify changes later
echo "Backing up initial configurations..."
docker cp "$CONTAINER:/var/ossec/etc/ossec.conf" /tmp/ossec_initial.conf
docker cp "$CONTAINER:/var/ossec/etc/decoders/local_decoder.xml" /tmp/decoder_initial.xml
docker cp "$CONTAINER:/var/ossec/etc/rules/local_rules.xml" /tmp/rules_initial.xml

# 3. Ensure Wazuh is running and healthy
echo "Ensuring Wazuh manager is ready..."
wait_for_service "Wazuh Manager" "docker exec $CONTAINER /var/ossec/bin/wazuh-control status | grep running" 60

# 4. Open Firefox to Dashboard (Rules section)
echo "Opening Dashboard..."
ensure_firefox_wazuh "${WAZUH_URL_RULES}"
sleep 5

# 5. Timestamp
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Log file created at: $LOG_FILE (inside wazuh-manager container)"