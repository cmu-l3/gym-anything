#!/bin/bash
# pre_task: Setup for web_attack_decoder_rules
echo "=== Setting up web_attack_decoder_rules ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Reset local_decoder.xml to baseline (remove any prior custom web decoders)
echo "Resetting local_decoder.xml to baseline..."
BASELINE_DECODER='<!-- Local Wazuh Decoders -->
<!-- Add your custom decoders below this comment -->
<!-- Reference: https://documentation.wazuh.com/current/user-manual/ruleset/decoders/decoders-syntax.html -->

<decoder name="local-decoder-example">
  <program_name>PLACEHOLDER_EXAMPLE</program_name>
</decoder>'

TEMP_DECODER=$(mktemp /tmp/decoder_reset.XXXXXX.xml)
echo "$BASELINE_DECODER" > "$TEMP_DECODER"
docker cp "$TEMP_DECODER" "${CONTAINER}:/var/ossec/etc/decoders/local_decoder.xml" && \
    echo "Decoders reset to baseline" || echo "WARNING: Could not reset decoders"
rm -f "$TEMP_DECODER"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null || true
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null || true

# Reset local_rules.xml to baseline (remove any prior web attack rules)
echo "Resetting local_rules.xml to baseline..."
BASELINE_RULES='<!-- Custom Wazuh rules for GymAnything environment -->
<group name="custom_rules,">

  <!-- SSH brute force detection -->
  <rule id="100001" level="10">
    <if_sid>5716</if_sid>
    <description>SSH authentication failure - possible password spraying</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
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

TEMP_RULES=$(mktemp /tmp/rules_reset.XXXXXX.xml)
echo "$BASELINE_RULES" > "$TEMP_RULES"
docker cp "$TEMP_RULES" "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" && \
    echo "Rules reset to baseline" || echo "WARNING: Could not reset rules"
rm -f "$TEMP_RULES"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true

# Record baseline state
echo "Recording baseline state..."
INITIAL_DECODER_COUNT=$(docker exec "${CONTAINER}" grep -c "<decoder name=" \
    /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null)
[ -z "$INITIAL_DECODER_COUNT" ] && INITIAL_DECODER_COUNT=0
echo "$INITIAL_DECODER_COUNT" > /tmp/initial_decoder_count

INITIAL_RULE_COUNT=$(docker exec "${CONTAINER}" grep -c "<rule " \
    /var/ossec/etc/rules/local_rules.xml 2>/dev/null)
[ -z "$INITIAL_RULE_COUNT" ] && INITIAL_RULE_COUNT=0
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Open Wazuh dashboard to rules/decoders management
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3
navigate_firefox_to "${WAZUH_URL_HOME}"
sleep 5

take_screenshot /tmp/web_attack_decoder_rules_start.png
echo "Initial screenshot saved."

echo ""
echo "=== Setup Complete ==="
echo "Baseline: local_decoder.xml reset (${INITIAL_DECODER_COUNT} decoder entries)"
echo "Baseline: local_rules.xml reset (${INITIAL_RULE_COUNT} rules)"
echo "Task: Create nginx access log decoder + 3 web attack detection rules"
echo "      (SQL injection level 10+, path traversal level 10+, cmd injection level 9+)"
echo "      At least one rule must have MITRE ATT&CK technique mapping"
echo ""
echo "Nginx access log format:"
echo '  <remote_ip> - <user> [<timestamp>] "<method> <uri> <protocol>" <status> <bytes> "<referer>" "<ua>"'
echo "  Example: 10.0.0.1 - - [14/Jan/2024:10:23:45 +0000] \"GET /index.php?id=1 HTTP/1.1\" 200 1234"
