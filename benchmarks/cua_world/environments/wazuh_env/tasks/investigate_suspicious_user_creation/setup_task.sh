#!/bin/bash
set -e
echo "=== Setting up task: Investigate Suspicious User Creation ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dashboard is open
echo "Ensuring Wazuh Dashboard is ready..."
ensure_firefox_wazuh "${WAZUH_URL_HOME}"

# 3. Generate Randomized Incident Data
# We generate a unique username and IP to prevent hardcoded answers
SUFFIX=$((RANDOM % 900 + 100))
BACKDOOR_USER="sysadmin_bk_${SUFFIX}"
# Generate a random IP (192.168.X.Y)
ATTACKER_IP="192.168.$((RANDOM % 250 + 1)).$((RANDOM % 250 + 1))"
TARGET_HOST="wazuh-manager"

echo "Generated IOCs: User=${BACKDOOR_USER}, IP=${ATTACKER_IP}"

# 4. Save Ground Truth (Hidden location)
# We store this in a location the agent is unlikely to look, but accessible for export
mkdir -p /var/lib/wazuh-dashboard
cat > /var/lib/wazuh-dashboard/ground_truth.json <<EOF
{
  "backdoor_username": "${BACKDOOR_USER}",
  "attacker_source_ip": "${ATTACKER_IP}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000+0000)"
}
EOF
chmod 644 /var/lib/wazuh-dashboard/ground_truth.json

# 5. Inject Logs into Wazuh Manager
# We simulate an attack chain: SSH Success -> Sudo -> User Creation
echo "Injecting attack logs into Wazuh manager..."

# Ensure auth.log exists inside container and is writable
docker exec -u root "${WAZUH_MANAGER_CONTAINER}" touch /var/log/auth.log
docker exec -u root "${WAZUH_MANAGER_CONTAINER}" chmod 666 /var/log/auth.log

# We inject logs with current timestamps so they appear at the top of the dashboard
# Using 'logger' inside container if available, else append to file
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "
    # Timestamps in syslog format (Mon DD HH:MM:SS)
    now=\$(date '+%b %d %H:%M:%S')
    
    # 1. SSH Login Success
    echo \"\$now ${TARGET_HOST} sshd[12345]: Accepted password for admin from ${ATTACKER_IP} port 54321 ssh2\" >> /var/log/auth.log
    
    # 2. Sudo session
    # slight delay to simulate human speed
    sleep 2
    now=\$(date '+%b %d %H:%M:%S')
    echo \"\$now ${TARGET_HOST} sudo:    admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; COMMAND=/bin/bash\" >> /var/log/auth.log
    echo \"\$now ${TARGET_HOST} sudo: pam_unix(sudo:session): session opened for user root by admin(uid=1000)\" >> /var/log/auth.log
    
    # 3. User Creation (UID 0 - The Alert Trigger)
    sleep 3
    now=\$(date '+%b %d %H:%M:%S')
    # Standard useradd log that triggers rule 5902
    echo \"\$now ${TARGET_HOST} useradd[12400]: new user: name=${BACKDOOR_USER}, UID=0, GID=0, home=/root, shell=/bin/bash\" >> /var/log/auth.log
    echo \"\$now ${TARGET_HOST} useradd[12400]: new group: name=${BACKDOOR_USER}, GID=0\" >> /var/log/auth.log
"

# 6. Wait for Indexing
echo "Waiting for logs to be indexed..."
sleep 5

# Verify Alert Generation (Optional debug)
# Check if the alert actually fired in the last minute
# We use the API to verify the environment is fair (alert exists)
TOKEN=$(get_api_token)
ALERT_CHECK=$(curl -sk -X GET "${WAZUH_API_URL}/alerts?search=${BACKDOOR_USER}&limit=1" \
    -H "Authorization: Bearer ${TOKEN}")

if echo "$ALERT_CHECK" | grep -q "${BACKDOOR_USER}"; then
    echo "Verification: Alert confirmed generated for ${BACKDOOR_USER}"
else
    echo "WARNING: Alert for ${BACKDOOR_USER} not found in API immediately. It might take a few seconds more."
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="