#!/bin/bash
echo "=== Setting up Detect Password Spraying Task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the simulation script
# This script generates logs that mimic a password spray (one IP, many users)
cat > /home/ga/generate_logs.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/megacorp.log"
# Ensure file exists and is writable
sudo touch $LOG_FILE
sudo chmod 666 $LOG_FILE

echo "Generating normal traffic..."
echo "$(date '+%Y-%m-%d %H:%M:%S') [MegaCorpERP] Auth: SUCCESS | User: admin | SrcIP: 10.0.0.5" >> $LOG_FILE
sleep 1

echo "Simulating Password Spraying Attack (1 IP, 5+ Users)..."
ATTACKER_IP="192.168.1.66"
USERS=("alice" "bob" "charlie" "dave" "eve" "mallory" "trent" "oscar")

for user in "${USERS[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') [MegaCorpERP] Auth: FAILED | User: $user | SrcIP: $ATTACKER_IP" >> $LOG_FILE
    sleep 0.2
done

echo "Simulation complete. Check alerts."
EOF
chmod +x /home/ga/generate_logs.sh
chown ga:ga /home/ga/generate_logs.sh

# 2. Initialize the log file
sudo touch /var/log/megacorp.log
sudo chmod 666 /var/log/megacorp.log

# 3. Clean up any previous configuration (if retrying)
CONTAINER="${WAZUH_MANAGER_CONTAINER}"
echo "Cleaning previous configurations in container..."

# Reset local_rules.xml to empty root
docker exec "${CONTAINER}" bash -c 'cat > /var/ossec/etc/rules/local_rules.xml << XMLEOF
<group name="local,">
</group>
XMLEOF' 2>/dev/null || true

# Reset local_decoder.xml to empty root
docker exec "${CONTAINER}" bash -c 'cat > /var/ossec/etc/decoders/local_decoder.xml << XMLEOF
<decoder name="local_decoder">
</decoder>
XMLEOF' 2>/dev/null || true

# Remove localfile config from ossec.conf if it matches our file
docker exec "${CONTAINER}" sed -i '/<location>\/var\/log\/megacorp.log<\/location>/d' /var/ossec/etc/ossec.conf 2>/dev/null || true
docker exec "${CONTAINER}" sed -i '/<log_format>syslog<\/log_format>/d' /var/ossec/etc/ossec.conf 2>/dev/null || true

# Restart manager to ensure clean state
echo "Restarting Wazuh manager..."
restart_wazuh_manager

# 4. Open Firefox to Dashboard
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 5. Timestamp
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="