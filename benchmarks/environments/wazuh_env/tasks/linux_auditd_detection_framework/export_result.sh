#!/bin/bash
# Export script for linux_auditd_detection_framework
# Checks decoder chain, detection rules, MITRE mapping, CDB list, and ossec.conf monitoring.

echo "=== Exporting linux_auditd_detection_framework Result ==="

source /workspace/scripts/task_utils.sh

if ! type wazuh_exec &>/dev/null; then
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_DECODER_COUNT=$(cat /tmp/initial_decoder_count 2>/dev/null || echo "0")
INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")

echo "Task start: $TASK_START"

# --- Check 1: Auditd decoder (parent + child pair) ---
echo "Checking decoder configuration..."

DECODER_XML=$(wazuh_exec "cat /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null || echo ''")

AUDIT_DECODER_FOUND=0
AUDIT_CHILD_DECODER_FOUND=0
AUDIT_DECODER_COUNT=0

if echo "$DECODER_XML" | grep -qiE 'name="[^"]*audit|program_name.*audit|<prematch>[^<]*audit'; then
    AUDIT_DECODER_FOUND=1
    # Count decoder entries referencing audit
    COUNT_OUT=$(echo "$DECODER_XML" | grep -c -iE 'name="[^"]*audit|<parent>[^<]*audit')
    if echo "$COUNT_OUT" | grep -qE '^[0-9]+$'; then
        AUDIT_DECODER_COUNT=$COUNT_OUT
    fi
    # Check for child decoder (has <parent> element pointing to audit decoder)
    if echo "$DECODER_XML" | grep -qiE '<parent>[^<]*audit'; then
        AUDIT_CHILD_DECODER_FOUND=1
    fi
fi
echo "Audit decoder: found=$AUDIT_DECODER_FOUND, child=$AUDIT_CHILD_DECODER_FOUND, count=$AUDIT_DECODER_COUNT"

# --- Check 2: Detection rules for auditd events ---
echo "Checking detection rules..."

RULES_XML=$(wazuh_exec "cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo ''")

# Count rules that reference auditd-related decoders or keywords
AUDITD_RULE_COUNT=0
PRIVESC_RULE=0
CRED_ACCESS_RULE=0
EXEC_RULE=0

if echo "$RULES_XML" | grep -qiE 'decoded_as.*audit|if_sid.*audit|privilege.escal|setuid|setgid|T1548|sudo|pkexec|escalat'; then
    PRIVESC_RULE=1
    AUDITD_RULE_COUNT=$((AUDITD_RULE_COUNT + 1))
fi

if echo "$RULES_XML" | grep -qiE '/etc/shadow|/etc/passwd|credential|T1003|passwd.*access|shadow.*access|credential.*access'; then
    CRED_ACCESS_RULE=1
    AUDITD_RULE_COUNT=$((AUDITD_RULE_COUNT + 1))
fi

if echo "$RULES_XML" | grep -qiE 'execve|suspicious.*exec|exec.*suspicious|T1059|process.*exec|T1106'; then
    EXEC_RULE=1
    AUDITD_RULE_COUNT=$((AUDITD_RULE_COUNT + 1))
fi

# Also count any rule with 'audit' in decoder reference
AUDIT_RULES_DIRECT=0
if echo "$RULES_XML" | grep -qiE 'decoded_as.*audit|<if_sid>.*audit|auditd.*rule'; then
    AUDIT_RULES_DIRECT=1
fi

TOTAL_AUDITD_RULES=$AUDITD_RULE_COUNT
[ "$AUDIT_RULES_DIRECT" -eq 1 ] && TOTAL_AUDITD_RULES=$((TOTAL_AUDITD_RULES > 0 ? TOTAL_AUDITD_RULES : 1))

echo "Auditd rules: total=$TOTAL_AUDITD_RULES (privesc=$PRIVESC_RULE, cred=$CRED_ACCESS_RULE, exec=$EXEC_RULE)"

# --- Check 3: MITRE ATT&CK mapping in at least one rule ---
echo "Checking for MITRE ATT&CK mappings..."

MITRE_FOUND=0
if echo "$RULES_XML" | grep -qE '<mitre>|<id>T[0-9]{4}|technique.*T[0-9]{4}'; then
    MITRE_FOUND=1
fi
echo "MITRE mapping found: $MITRE_FOUND"

# --- Check 4: CDB lookup list with high-risk executables ---
echo "Checking CDB lists..."

CDB_LIST_FOUND=0
CDB_ENTRY_COUNT=0
# Look for CDB files containing executable paths in /var/ossec/etc/lists/
CDB_FILES=$(wazuh_exec "ls /var/ossec/etc/lists/ 2>/dev/null || echo ''")
for cdb_file in $CDB_FILES; do
    CONTENT=$(wazuh_exec "cat /var/ossec/etc/lists/${cdb_file} 2>/dev/null || echo ''")
    # Check for executable paths (start with /)
    if echo "$CONTENT" | grep -qE '^/usr/|^/bin/|^/sbin/'; then
        CDB_LIST_FOUND=1
        FILE_ENTRIES=$(echo "$CONTENT" | grep -c -E '^/usr/|^/bin/|^/sbin/')
        if echo "$FILE_ENTRIES" | grep -qE '^[0-9]+$'; then
            CDB_ENTRY_COUNT=$((CDB_ENTRY_COUNT + FILE_ENTRIES))
        fi
    fi
done
echo "CDB executable list: found=$CDB_LIST_FOUND, entries=$CDB_ENTRY_COUNT"

# --- Check 5: ossec.conf monitoring audit.log ---
echo "Checking ossec.conf for audit.log monitoring..."

OSSEC_CONF=$(wazuh_exec "cat /var/ossec/etc/ossec.conf 2>/dev/null || echo ''")
AUDIT_LOG_MONITORED=0

if echo "$OSSEC_CONF" | grep -qE '/var/log/audit/audit\.log|/var/log/audit\b|audit\.log'; then
    AUDIT_LOG_MONITORED=1
fi
echo "Audit log monitored in ossec.conf: $AUDIT_LOG_MONITORED"

# Current totals
CURRENT_DECODER_COUNT=0
DEC_COUNT_OUT=$(echo "$DECODER_XML" | grep -c '<decoder name=')
if echo "$DEC_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_DECODER_COUNT=$DEC_COUNT_OUT
fi

CURRENT_RULE_COUNT=0
RULE_COUNT_OUT=$(echo "$RULES_XML" | grep -c '<rule id=')
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_RULE_COUNT=$RULE_COUNT_OUT
fi

# Write result JSON
cat > /tmp/linux_auditd_detection_framework_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "audit_decoder_found": ${AUDIT_DECODER_FOUND},
    "audit_child_decoder_found": ${AUDIT_CHILD_DECODER_FOUND},
    "audit_decoder_count": ${AUDIT_DECODER_COUNT},
    "total_auditd_rules": ${TOTAL_AUDITD_RULES},
    "privesc_rule": ${PRIVESC_RULE},
    "cred_access_rule": ${CRED_ACCESS_RULE},
    "exec_rule": ${EXEC_RULE},
    "mitre_found": ${MITRE_FOUND},
    "cdb_list_found": ${CDB_LIST_FOUND},
    "cdb_entry_count": ${CDB_ENTRY_COUNT},
    "audit_log_monitored": ${AUDIT_LOG_MONITORED},
    "current_decoder_count": ${CURRENT_DECODER_COUNT},
    "current_rule_count": ${CURRENT_RULE_COUNT},
    "initial_decoder_count": ${INITIAL_DECODER_COUNT},
    "initial_rule_count": ${INITIAL_RULE_COUNT}
}
JSONEOF

echo "Result JSON written to /tmp/linux_auditd_detection_framework_result.json"
python3 -m json.tool /tmp/linux_auditd_detection_framework_result.json > /dev/null 2>&1 && echo "JSON valid" || echo "WARNING: JSON may be malformed"

echo "=== Export Complete ==="
