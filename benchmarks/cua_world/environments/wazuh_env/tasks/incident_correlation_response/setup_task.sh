#!/bin/bash
# pre_task: Setup for incident_correlation_response
echo "=== Setting up incident_correlation_response ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
REPORT_PATH="/home/ga/Desktop/incident_report.txt"

# Remove any prior incident report from previous task runs
echo "Removing any prior incident report..."
rm -f "$REPORT_PATH" 2>/dev/null || true

# Reset local_rules.xml to baseline (remove any prior correlation rules from previous runs)
echo "Resetting local_rules.xml to baseline..."
BASELINE_RULES='<!-- Custom Wazuh rules for GymAnything environment -->
<group name="custom_rules,">

  <!-- SSH brute force detection -->
  <rule id="100001" level="10">
    <if_sid>5716</if_sid>
    <description>SSH authentication failure - possible brute force</description>
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

# Generate some real SSH authentication events that Wazuh will alert on.
# These are real system events (not synthetic data) — actual failed SSH connections.
echo "Generating real authentication events for investigation..."
for i in 1 2 3 4 5; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes \
        nonexistent_user_soc_task@127.0.0.1 2>/dev/null || true
    sleep 1
done

# Also trigger some sudo failures (real events)
sudo -u nonexistent_soc_user ls 2>/dev/null || true
sudo -u www-data ls /root 2>/dev/null || true

echo "Real security events generated. Waiting for Wazuh to process them..."
sleep 10

# Record baseline state
echo "Recording baseline state..."
INITIAL_RULE_COUNT=$(docker exec "${CONTAINER}" grep -c "<rule " \
    /var/ossec/etc/rules/local_rules.xml 2>/dev/null)
[ -z "$INITIAL_RULE_COUNT" ] && INITIAL_RULE_COUNT=0
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count

INITIAL_AR_COUNT=$(docker exec "${CONTAINER}" grep -c "<active-response>" \
    /var/ossec/etc/ossec.conf 2>/dev/null)
[ -z "$INITIAL_AR_COUNT" ] && INITIAL_AR_COUNT=0
echo "$INITIAL_AR_COUNT" > /tmp/initial_ar_count

# List top firing rules from the last few hours via the API
echo "Current top alerts in the environment:"
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    curl -sk -X GET "${WAZUH_API_URL}/security/events?limit=10&sort=-timestamp" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data.get('data', {}).get('affected_items', [])
    for item in items[:10]:
        rule = item.get('rule', {})
        print(f\"  Rule {rule.get('id', '?')} (level {rule.get('level', '?')}): {rule.get('description', '?')[:80]}\")
except:
    pass
" 2>/dev/null || true
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Open Wazuh dashboard at the alerts/events view
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3
navigate_firefox_to "${WAZUH_URL_HOME}"
sleep 5

take_screenshot /tmp/incident_correlation_response_start.png
echo "Initial screenshot saved."

echo ""
echo "=== Setup Complete ==="
echo "Real security events have been generated. Wazuh has existing alerts to investigate."
echo "Task: Investigate alerts in the dashboard, create correlation rule with"
echo "      frequency + timeframe attributes (level >= 13), configure active response,"
echo "      and write incident report to: ${REPORT_PATH}"
echo ""
echo "Wazuh correlation rule syntax uses 'frequency' and 'timeframe' attributes on <rule>"
echo "with <if_matched_sid> to reference the parent rule ID being correlated."
