#!/bin/bash
# post_task: Export results for threat_intel_cdb_rules
echo "=== Exporting threat_intel_cdb_rules Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

# === Check 1: CDB list with IP entries in /var/ossec/etc/lists/ ===
CDB_LIST_EXISTS=0
CDB_ENTRY_COUNT=0

LIST_CHECK_RESULT=$(docker exec "${CONTAINER}" bash -c '
max_count=0
for f in /var/ossec/etc/lists/*; do
    [ -f "$f" ] || continue
    case "$f" in *.db|*.cdb) continue;; esac
    fname=$(basename "$f")
    case "$fname" in audit-keys|security-eventchannel|amazon-*) continue;; esac
    count=$(grep -cE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" "$f" 2>/dev/null)
    [ -z "$count" ] && count=0
    if [ "$count" -gt "$max_count" ]; then
        max_count=$count
    fi
done
echo $max_count
' 2>/dev/null || echo "0")

[ -z "$LIST_CHECK_RESULT" ] && LIST_CHECK_RESULT=0
if [ "$LIST_CHECK_RESULT" -gt 0 ] 2>/dev/null; then
    CDB_LIST_EXISTS=1
    CDB_ENTRY_COUNT=$LIST_CHECK_RESULT
fi

# === Check 2: ossec.conf has a CUSTOM (non-default) CDB list declaration ===
# Default Wazuh ships with audit-keys, security-eventchannel, amazon/aws-eventnames.
# We only award this criterion if the agent added a custom (new) list entry.
OSSEC_HAS_LIST_DECL=0

CUSTOM_LIST_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
DEFAULT_LISTS = ['audit-keys', 'security-eventchannel', 'amazon/aws-eventnames', 'amazon']
try:
    tree = ET.parse('/var/ossec/etc/ossec.conf')
    root = tree.getroot()
    for ruleset in root.iter('ruleset'):
        for lst in ruleset.iter('list'):
            if lst.text:
                text = lst.text.strip()
                if not any(d in text for d in DEFAULT_LISTS):
                    print('found:' + text)
                    exit(0)
    print('not_found')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null || echo "not_found")

if echo "$CUSTOM_LIST_CHECK" | grep -q "^found:"; then
    OSSEC_HAS_LIST_DECL=1
fi

# Also check host-mounted config as fallback (same exclusion logic)
HOST_CUSTOM_LIST=$(python3 -c "
import xml.etree.ElementTree as ET
DEFAULT_LISTS = ['audit-keys', 'security-eventchannel', 'amazon/aws-eventnames', 'amazon']
try:
    tree = ET.parse('/home/ga/wazuh/config/wazuh_cluster/wazuh_manager.conf')
    root = tree.getroot()
    for ruleset in root.iter('ruleset'):
        for lst in ruleset.iter('list'):
            if lst.text:
                text = lst.text.strip()
                if not any(d in text for d in DEFAULT_LISTS):
                    print('found')
                    exit(0)
    print('not_found')
except Exception:
    print('not_found')
" 2>/dev/null || echo "not_found")
if echo "$HOST_CUSTOM_LIST" | grep -q "^found"; then
    OSSEC_HAS_LIST_DECL=1
fi

# === Check 3: Rules in local_rules.xml using CDB list lookup (<list> element) ===
RULES_WITH_CDB=0
MAX_CDB_RULE_LEVEL=0

RULES_CDB_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/var/ossec/etc/rules/local_rules.xml')
    root = tree.getroot()
    count = 0
    max_level = 0
    for rule in root.iter('rule'):
        if rule.find('list') is not None:
            count += 1
            level = int(rule.get('level', 0))
            if level > max_level:
                max_level = level
    print(f'{count},{max_level}')
except Exception as e:
    print('0,0')
" 2>/dev/null || echo "0,0")

RULES_WITH_CDB=$(echo "$RULES_CDB_CHECK" | cut -d',' -f1)
MAX_CDB_RULE_LEVEL=$(echo "$RULES_CDB_CHECK" | cut -d',' -f2)
[ -z "$RULES_WITH_CDB" ] && RULES_WITH_CDB=0
[ -z "$MAX_CDB_RULE_LEVEL" ] && MAX_CDB_RULE_LEVEL=0

# Create result JSON
cat > /tmp/threat_intel_cdb_rules_result.json << EOF
{
    "task_start": ${TASK_START},
    "cdb_list_exists": ${CDB_LIST_EXISTS},
    "cdb_entry_count": ${CDB_ENTRY_COUNT},
    "ossec_has_list_declaration": ${OSSEC_HAS_LIST_DECL},
    "rules_with_cdb_lookup": ${RULES_WITH_CDB},
    "max_cdb_rule_level": ${MAX_CDB_RULE_LEVEL},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/threat_intel_cdb_rules_result.json
echo "=== Export Complete ==="
