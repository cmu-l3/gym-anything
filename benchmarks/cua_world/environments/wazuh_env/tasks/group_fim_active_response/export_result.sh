#!/bin/bash
# post_task: Export results for group_fim_active_response
echo "=== Exporting group_fim_active_response Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TARGET_GROUP="critical-servers"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_AR_COUNT=$(cat /tmp/initial_ar_count 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

TOKEN=$(get_api_token)

# === Check 1: Group 'critical-servers' exists ===
GROUP_EXISTS=0
if [ -n "$TOKEN" ]; then
    GROUP_CHECK=$(curl -sk -X GET "${WAZUH_API_URL}/groups?search=${TARGET_GROUP}" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    if echo "$GROUP_CHECK" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
exit(0 if any(i.get('name') == '${TARGET_GROUP}' for i in items) else 1)
" 2>/dev/null; then
        GROUP_EXISTS=1
    fi
fi

# === Check 2: Agent 000 is member of critical-servers group ===
AGENT_IN_GROUP=0
AGENT_GROUPS_STR=""
if [ -n "$TOKEN" ]; then
    AGENT_GROUPS_STR=$(curl -sk -X GET "${WAZUH_API_URL}/agents/000?select=group" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
groups = items[0].get('group', []) if items else []
print(','.join(groups))
" 2>/dev/null || echo "")
    if echo "$AGENT_GROUPS_STR" | grep -q "${TARGET_GROUP}"; then
        AGENT_IN_GROUP=1
    fi
fi

# === Check 3: Group agent.conf has FIM (syscheck) configuration ===
FIM_CONFIGURED=0
FIM_PATHS_FOUND=""
SHARED_DIR="/var/ossec/etc/shared/${TARGET_GROUP}"

if docker exec "${CONTAINER}" test -f "${SHARED_DIR}/agent.conf" 2>/dev/null; then
    FIM_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('${SHARED_DIR}/agent.conf')
    root = tree.getroot()
    paths_found = []
    critical_paths = ['/etc/passwd', '/etc/shadow', '/etc/ssh', '/etc/audit', '/var/log/auth']
    for syscheck in root.iter('syscheck'):
        for dirs in syscheck.iter('directories'):
            dir_text = dirs.text.strip() if dirs.text else ''
            for cp in critical_paths:
                if cp in dir_text:
                    if cp not in paths_found:
                        paths_found.append(cp)
    if paths_found:
        print('found:' + ','.join(paths_found))
    else:
        print('not_found')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null || echo "not_found")

    if echo "$FIM_CHECK" | grep -q "^found:"; then
        FIM_CONFIGURED=1
        FIM_PATHS_FOUND=$(echo "$FIM_CHECK" | cut -d':' -f2-)
    fi
fi

# === Check 4: Custom FIM detection rule exists (level >= 10, referencing FIM parent rules) ===
FIM_RULE_EXISTS=0
FIM_RULE_LEVEL=0

FIM_RULE_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/var/ossec/etc/rules/local_rules.xml')
    root = tree.getroot()
    max_level = 0
    found = False
    # FIM parent rule SIDs in Wazuh: 550-556 (syscheck), 553 (file modified), 554 (file added), etc.
    fim_sids = {'550','551','552','553','554','555','556','594','597','598','750','751','752','753','754'}
    for rule in root.iter('rule'):
        level = int(rule.get('level', 0))
        is_fim = False
        # Check if_sid references FIM parent rules
        if_sid = rule.find('if_sid')
        if if_sid is not None and if_sid.text:
            for sid in if_sid.text.replace(',', ' ').split():
                if sid.strip() in fim_sids:
                    is_fim = True
        # Check if rule is in syscheck or fim group
        for grp in rule.iter('group'):
            if grp.text and ('syscheck' in grp.text.lower() or 'fim' in grp.text.lower() or 'integrity' in grp.text.lower()):
                is_fim = True
        # Check description for FIM-related keywords
        for desc in rule.iter('description'):
            if desc.text and any(kw in desc.text.lower() for kw in ['shadow', 'passwd', 'fim', 'integrity', 'critical file', 'syscheck']):
                if level >= 8:
                    is_fim = True
        # Check match for file paths
        for match_el in rule.iter('match'):
            if match_el.text and any(kw in match_el.text for kw in ['/etc/shadow', '/etc/passwd', '/etc/ssh']):
                is_fim = True
        if is_fim and level >= 10:
            found = True
            if level > max_level:
                max_level = level
    print(f'{1 if found else 0},{max_level}')
except Exception as e:
    print('0,0')
" 2>/dev/null || echo "0,0")

FIM_RULE_EXISTS=$(echo "$FIM_RULE_CHECK" | cut -d',' -f1)
FIM_RULE_LEVEL=$(echo "$FIM_RULE_CHECK" | cut -d',' -f2)
[ -z "$FIM_RULE_EXISTS" ] && FIM_RULE_EXISTS=0
[ -z "$FIM_RULE_LEVEL" ] && FIM_RULE_LEVEL=0

# === Check 5: Active response configured in ossec.conf ===
ACTIVE_RESPONSE_CONFIGURED=0

CURRENT_AR_COUNT=$(docker exec "${CONTAINER}" grep -c "<active-response>" \
    /var/ossec/etc/ossec.conf 2>/dev/null)
[ -z "$CURRENT_AR_COUNT" ] && CURRENT_AR_COUNT=0

if [ "$CURRENT_AR_COUNT" -gt "$INITIAL_AR_COUNT" ] 2>/dev/null; then
    ACTIVE_RESPONSE_CONFIGURED=1
fi

# Check host-mounted config as fallback (agent may have edited wazuh_manager.conf directly).
# Compare against INITIAL_AR_COUNT to avoid false positives from pre-existing AR entries.
HOST_AR=$(grep -c "<active-response>" \
    /home/ga/wazuh/config/wazuh_cluster/wazuh_manager.conf 2>/dev/null)
[ -z "$HOST_AR" ] && HOST_AR=0
if [ "$HOST_AR" -gt "$INITIAL_AR_COUNT" ] 2>/dev/null; then
    ACTIVE_RESPONSE_CONFIGURED=1
fi

# Create result JSON
cat > /tmp/group_fim_active_response_result.json << EOF
{
    "task_start": ${TASK_START},
    "group_exists": ${GROUP_EXISTS},
    "agent_000_in_group": ${AGENT_IN_GROUP},
    "agent_000_groups": "${AGENT_GROUPS_STR}",
    "fim_configured_in_group": ${FIM_CONFIGURED},
    "fim_paths_found": "${FIM_PATHS_FOUND}",
    "fim_rule_exists": ${FIM_RULE_EXISTS},
    "fim_rule_level": ${FIM_RULE_LEVEL},
    "active_response_configured": ${ACTIVE_RESPONSE_CONFIGURED},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/group_fim_active_response_result.json
echo "=== Export Complete ==="
