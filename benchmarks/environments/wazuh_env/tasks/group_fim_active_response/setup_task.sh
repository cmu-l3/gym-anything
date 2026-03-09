#!/bin/bash
# pre_task: Setup for group_fim_active_response
echo "=== Setting up group_fim_active_response ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TARGET_GROUP="critical-servers"

# Remove the target group if it exists (ensure clean state)
echo "Cleaning up any existing '${TARGET_GROUP}' group..."
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    EXISTING=$(curl -sk -X GET "${WAZUH_API_URL}/groups?search=${TARGET_GROUP}" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    if echo "$EXISTING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
exit(0 if any(i.get('name') == '${TARGET_GROUP}' for i in items) else 1)
" 2>/dev/null; then
        echo "Removing existing '${TARGET_GROUP}' group..."
        curl -sk -X DELETE "${WAZUH_API_URL}/groups?groups_list=${TARGET_GROUP}" \
            -H "Authorization: Bearer ${TOKEN}" > /dev/null 2>&1 || true
        sleep 3
    fi
fi

# Remove agent 000 from any non-default groups (reset to 'default' group only)
echo "Resetting agent 000 to default group only..."
if [ -n "$TOKEN" ]; then
    AGENT_GROUPS=$(curl -sk -X GET "${WAZUH_API_URL}/agents/000?select=group" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
groups = items[0].get('group', ['default']) if items else ['default']
non_default = [g for g in groups if g != 'default']
print(','.join(non_default))
" 2>/dev/null || echo "")

    if [ -n "$AGENT_GROUPS" ]; then
        echo "Removing agent 000 from extra groups: $AGENT_GROUPS"
        IFS=',' read -ra GRPARRAY <<< "$AGENT_GROUPS"
        for grp in "${GRPARRAY[@]}"; do
            [ -z "$grp" ] && continue
            curl -sk -X DELETE "${WAZUH_API_URL}/agents/000/group/${grp}" \
                -H "Authorization: Bearer ${TOKEN}" > /dev/null 2>&1 || true
        done
        sleep 2
    fi
fi

# Reset local_rules.xml to baseline (remove any prior FIM-related custom rules)
echo "Resetting local_rules.xml to baseline..."
BASELINE_RULES='<!-- Custom Wazuh rules for GymAnything environment -->
<group name="custom_rules,">

  <!-- SSH brute force detection -->
  <rule id="100001" level="10">
    <if_sid>5716</if_sid>
    <description>SSH authentication failure - possible brute force</description>
    <group>authentication_failed,</group>
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
INITIAL_GROUPS=$(curl -sk -X GET "${WAZUH_API_URL}/groups" \
    -H "Authorization: Bearer $(get_api_token)" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
print(','.join(i.get('name', '') for i in items))
" 2>/dev/null || echo "")
echo "$INITIAL_GROUPS" > /tmp/initial_groups

AGENT_000_GROUPS=$(curl -sk -X GET "${WAZUH_API_URL}/agents/000?select=group" \
    -H "Authorization: Bearer $(get_api_token)" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
groups = items[0].get('group', ['default']) if items else ['default']
print(','.join(groups))
" 2>/dev/null || echo "default")
echo "$AGENT_000_GROUPS" > /tmp/initial_agent_000_groups

INITIAL_RULE_COUNT=$(docker exec "${CONTAINER}" grep -c "<rule " \
    /var/ossec/etc/rules/local_rules.xml 2>/dev/null)
[ -z "$INITIAL_RULE_COUNT" ] && INITIAL_RULE_COUNT=0
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count

INITIAL_AR_COUNT=$(docker exec "${CONTAINER}" grep -c "<active-response>" \
    /var/ossec/etc/ossec.conf 2>/dev/null)
[ -z "$INITIAL_AR_COUNT" ] && INITIAL_AR_COUNT=0
echo "$INITIAL_AR_COUNT" > /tmp/initial_ar_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Open Wazuh dashboard
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3
navigate_firefox_to "${WAZUH_URL_HOME}"
sleep 5

take_screenshot /tmp/group_fim_active_response_start.png
echo "Initial screenshot saved."

echo ""
echo "=== Setup Complete ==="
echo "Current agent groups: $INITIAL_GROUPS"
echo "Agent 000 groups: $AGENT_000_GROUPS"
echo "Task: Create 'critical-servers' group with FIM for /etc/passwd, /etc/shadow,"
echo "      /etc/ssh/, /etc/audit/, /var/log/auth.log; assign agent 000;"
echo "      create FIM detection rule (level >= 12); configure active response"
