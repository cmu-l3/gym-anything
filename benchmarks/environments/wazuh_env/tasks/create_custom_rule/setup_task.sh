#!/bin/bash
# pre_task: Setup for create_custom_rule task
echo "=== Setting up create_custom_rule task ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TARGET_RULE_ID=100010

# Reset local_rules.xml to baseline (without rule 100010)
echo "Resetting local_rules.xml to baseline..."
BASELINE_RULES='<!-- Custom Wazuh rules for GymAnything environment -->
<group name="custom_rules,">

  <!-- SSH brute force detection -->
  <rule id="100001" level="10">
    <if_sid>5716</if_sid>
    <description>SSH authentication failure - possible brute force</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,gpg13_7.1,gdpr_IV_35.7.d,hipaa_164.312.b,nist_800_53_AU.14,nist_800_53_AC.7,tsc_CC6.1,tsc_CC6.8,tsc_CC7.2,tsc_CC7.3,</group>
  </rule>

  <!-- Failed sudo attempts -->
  <rule id="100002" level="8">
    <if_sid>5401</if_sid>
    <match>incorrect password attempts</match>
    <description>Failed sudo attempt detected</description>
    <group>sudo_failed,authentication_failed,</group>
  </rule>

  <!-- High CPU usage alert -->
  <rule id="100003" level="7">
    <if_sid>530</if_sid>
    <match>CPU usage is high</match>
    <description>High CPU usage detected on agent</description>
    <group>system_monitor,</group>
  </rule>

</group>'

TEMP_RULES=$(mktemp /tmp/local_rules.XXXXXX.xml)
echo "$BASELINE_RULES" > "$TEMP_RULES"
docker cp "$TEMP_RULES" "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" && \
    echo "Copied baseline rules to container" || echo "WARNING: Could not copy rules"
rm -f "$TEMP_RULES"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true

echo "local_rules.xml reset to baseline (rule ${TARGET_RULE_ID} not present)"

# Navigate to Wazuh Rules management page
echo "Opening Wazuh Rules management page..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3

navigate_firefox_to "${WAZUH_URL_RULES}"
sleep 6

take_screenshot /tmp/create_custom_rule_initial.png
echo "Initial screenshot saved to /tmp/create_custom_rule_initial.png"

echo "=== create_custom_rule task setup complete ==="
echo "Task: Add rule ID 100010 to local_rules.xml via the dashboard editor"
echo "Rule properties: level=9, if_sid=5710, description='Invalid SSH user detected - potential unauthorized access attempt'"
echo "Navigate to: Management > Rules > Custom rules tab > Edit local_rules.xml"
