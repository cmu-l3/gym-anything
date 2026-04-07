#!/bin/bash
set -e
echo "=== Setting up detect_data_staging_activity task ==="

source /workspace/scripts/task_utils.sh

# 1. Create Data Directory and Sample Logs
mkdir -p /home/ga/data
LOG_FILE="/home/ga/data/audit_staging_sample.log"

cat > "$LOG_FILE" << 'EOF'
type=EXECVE msg=audit(1698234001.123:101): argc=4 a0="tar" a1="-czf" a2="/tmp/backup_sensitive.tar.gz" a3="/opt/sensitive_project"
type=EXECVE msg=audit(1698234055.456:102): argc=4 a0="tar" a1="-czf" a2="/tmp/my_docs.tar.gz" a3="/home/user/documents"
type=EXECVE msg=audit(1698234120.789:103): argc=2 a0="ls" a1="-la" a2="/opt/sensitive_project"
EOF

chown ga:ga "$LOG_FILE"
chmod 644 "$LOG_FILE"

# 2. Reset local_rules.xml to clean state
CONTAINER="${WAZUH_MANAGER_CONTAINER}"
echo "Resetting local_rules.xml in container $CONTAINER..."

# Check if container is running
if ! docker ps | grep -q "$CONTAINER"; then
    echo "Starting Wazuh manager container..."
    docker-compose -f /home/ga/wazuh/docker-compose.yml up -d wazuh.manager
    sleep 20
fi

# Overwrite local_rules.xml with empty group
docker exec "$CONTAINER" bash -c 'cat > /var/ossec/etc/rules/local_rules.xml << XML
<!-- Local rules -->
<group name="local,">
</group>
XML'

docker exec "$CONTAINER" chown root:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec "$CONTAINER" chmod 660 /var/ossec/etc/rules/local_rules.xml

# Restart manager to ensure clean state loaded
# docker exec "$CONTAINER" /var/ossec/bin/wazuh-control restart > /dev/null 2>&1 || true

# 3. Open Terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/data &"
    sleep 2
fi

# Focus terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# 4. Open the log file in a text editor for visibility
if ! pgrep -f "gedit" > /dev/null; then
    su - ga -c "DISPLAY=:1 gedit $LOG_FILE &"
    sleep 3
fi

# Arrange windows
DISPLAY=:1 wmctrl -r "gedit" -e 0,0,0,900,600 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Terminal" -e 0,900,0,900,600 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="