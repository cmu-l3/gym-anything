#!/bin/bash
echo "=== Setting up Configure Time-Based Suppression task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Ensure we start with a clean local_rules.xml (remove our target rule if it exists)
echo "Cleaning local_rules.xml..."
docker exec "${CONTAINER}" bash -c "
    if grep -q 'id=\"100250\"' /var/ossec/etc/rules/local_rules.xml; then
        # Remove the specific rule block if it exists (simple sed deletion for a known block structure won't work easily for XML)
        # Instead, reset to a known safe baseline if the rule is detected
        cat > /var/ossec/etc/rules/local_rules.xml << 'EOF'
<!-- Local rules -->
<group name=\"local,syslog,sshd,\">
  <!-- Add your custom rules here -->
</group>
EOF
        chown root:wazuh /var/ossec/etc/rules/local_rules.xml
        chmod 660 /var/ossec/etc/rules/local_rules.xml
        /var/ossec/bin/wazuh-control restart
    fi
" 2>/dev/null || true

# Verify Wazuh manager is running
if ! docker ps | grep -q "${CONTAINER}"; then
    echo "Starting Wazuh manager container..."
    docker start "${CONTAINER}"
    sleep 10
fi

# Open Firefox to the Rules section to provide a GUI starting point
echo "Opening Wazuh Rules management page..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Navigate specifically to Custom Rules
navigate_firefox_to "https://localhost/app/rules#/manager/?tab=custom-rules"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="