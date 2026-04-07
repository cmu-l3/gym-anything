#!/bin/bash
set -e
echo "=== Setting up create_custom_decoder task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Sample Data
mkdir -p /home/ga/bastion_logs
cat > /home/ga/bastion_logs/sample_bastion.log << 'EOF'
Jan 15 10:23:45 bastion-gw session_auth[5234]: user=jsmith src_ip=192.168.1.50 action=login status=failed reason="invalid_credentials"
Jan 15 10:24:12 bastion-gw session_auth[5235]: user=admin src_ip=10.0.0.5 action=login status=success reason="key_auth"
Jan 15 10:25:01 bastion-gw session_auth[5236]: user=root src_ip=203.0.113.42 action=login status=failed reason="account_locked"
Jan 15 10:30:00 bastion-gw session_auth[5240]: user=deploy src_ip=172.16.0.10 action=sudo status=failed reason="not_in_sudoers"
Jan 15 10:35:22 bastion-gw session_auth[5244]: user=jsmith src_ip=192.168.1.50 action=login status=success reason="password_auth"
EOF
chown -R ga:ga /home/ga/bastion_logs

# 2. Reset local_decoder.xml and local_rules.xml to known clean state
# We use docker exec to modify files inside the manager container
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

echo "Resetting configuration files..."

# Empty local_decoder.xml
cat > /tmp/clean_decoder.xml << 'EOF'
<!-- Local Decoders -->
<decoder name="local_decoder_example">
    <program_name>example_program</program_name>
</decoder>
EOF
docker cp /tmp/clean_decoder.xml "${CONTAINER}:/var/ossec/etc/decoders/local_decoder.xml"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/decoders/local_decoder.xml
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/decoders/local_decoder.xml

# Baseline local_rules.xml
cat > /tmp/clean_rules.xml << 'EOF'
<!-- Local Rules -->
<group name="local,">
  <rule id="100001" level="0">
    <decoded_as>local_decoder_example</decoded_as>
    <description>Example rule</description>
  </rule>
</group>
EOF
docker cp /tmp/clean_rules.xml "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/rules/local_rules.xml

# Restart manager to ensure clean state load
echo "Restarting Wazuh manager to apply clean state..."
docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control restart > /dev/null 2>&1
sleep 5

# 3. Open Terminal for the agent (they need to run wazuh-logtest or edit files)
# We'll also open the sample log file in a text editor for convenience
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30+100+100 -- bash -c 'cat /home/ga/bastion_logs/sample_bastion.log; echo \"Sample logs loaded above.\"; exec bash'" &
    sleep 2
fi

# 4. Open Firefox to Wazuh Dashboard (as an alternative tool)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Focus the terminal initially as this is a backend/sysadmin task
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="