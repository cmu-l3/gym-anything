#!/bin/bash
# setup_task.sh for tune_rule_false_positives

echo "=== Setting up tune_rule_false_positives task ==="
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (restart detection)
date +%s > /tmp/task_start_time.txt

# 2. Reset local_rules.xml to a known clean state
# We want to ensure it doesn't already contain our target rules
echo "Resetting local_rules.xml..."
cat > /tmp/local_rules_clean.xml << 'EOF'
<!-- Local rules -->
<group name="local,syslog,">
</group>
EOF

# Copy to container
wazuh_exec bash -c "cat > /var/ossec/etc/rules/local_rules.xml" < /tmp/local_rules_clean.xml
wazuh_exec chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml
wazuh_exec chmod 660 /var/ossec/etc/rules/local_rules.xml

# Restart manager to apply clean state if needed (skip if we want to be fast, 
# but safest to ensure rule 5402 is at default level)
# For setup speed, we'll assume the environment is reasonably clean or just rely on the file overwrite.
# If previous run left bad rules, the agent needs to fix it anyway.

# 3. Verify services are up
echo "Waiting for Wazuh API..."
wait_for_service "Wazuh API" "check_api_health" 60

# 4. Open Firefox to Rules section
echo "Opening Firefox to Rules..."
ensure_firefox_wazuh "${WAZUH_URL_RULES}"

# 5. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

# 6. Record initial checksum of local_rules.xml
wazuh_exec md5sum /var/ossec/etc/rules/local_rules.xml | awk '{print $1}' > /tmp/initial_rules_md5.txt

echo "=== Setup complete ==="