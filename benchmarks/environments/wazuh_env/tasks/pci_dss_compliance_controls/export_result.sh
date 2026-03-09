#!/bin/bash
# Export script for pci_dss_compliance_controls
# Checks SCA policy, email config, detection rules, ossec.conf, and compliance report.

echo "=== Exporting pci_dss_compliance_controls Result ==="

source /workspace/scripts/task_utils.sh

if ! type wazuh_exec &>/dev/null; then
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")

echo "Task start: $TASK_START"

# --- Check 1: PCI DSS SCA policy YAML with >=5 checks ---
echo "Checking for PCI DSS SCA policy..."

PCI_POLICY_FOUND=0
PCI_CHECK_COUNT=0
PCI_POLICY_NAME=""

# Search all YAML/YML files in shared directory for PCI-related content
SHARED_FILES=$(wazuh_exec "find /var/ossec/etc/shared -name '*.yaml' -o -name '*.yml' 2>/dev/null")
for sca_file in $SHARED_FILES; do
    CONTENT=$(wazuh_exec "cat '${sca_file}' 2>/dev/null || echo ''")
    if echo "$CONTENT" | grep -qiE 'pci|payment.*card|cardholder|PCI DSS|PCI-DSS|requirement.*10|req.*10'; then
        PCI_POLICY_FOUND=1
        # Count check entries (lines with 'id:' at the check level)
        CHECK_COUNT=$(echo "$CONTENT" | grep -c '^\s*- id:')
        if ! echo "$CHECK_COUNT" | grep -qE '^[0-9]+$'; then
            CHECK_COUNT=0
        fi
        if [ "$CHECK_COUNT" -gt "$PCI_CHECK_COUNT" ]; then
            PCI_CHECK_COUNT=$CHECK_COUNT
            PCI_POLICY_NAME="$sca_file"
        fi
    fi
done
echo "PCI SCA policy: found=$PCI_POLICY_FOUND, checks=$PCI_CHECK_COUNT, file=$PCI_POLICY_NAME"

# --- Check 2: Email alerting configuration in ossec.conf ---
echo "Checking email alerting configuration..."

OSSEC_CONF=$(wazuh_exec "cat /var/ossec/etc/ossec.conf 2>/dev/null || echo ''")

EMAIL_CONFIGURED=0
EMAIL_TO_SET=0
EMAIL_SMTP_SET=0
EMAIL_FROM_SET=0

if echo "$OSSEC_CONF" | grep -q '<email_to>'; then
    EMAIL_TO_SET=1
    EMAIL_CONFIGURED=1
fi
if echo "$OSSEC_CONF" | grep -qE '<smtp_server>|<email_smtp>'; then
    EMAIL_SMTP_SET=1
    EMAIL_CONFIGURED=1
fi
if echo "$OSSEC_CONF" | grep -q '<email_from>'; then
    EMAIL_FROM_SET=1
fi
echo "Email: configured=$EMAIL_CONFIGURED, to=$EMAIL_TO_SET, smtp=$EMAIL_SMTP_SET, from=$EMAIL_FROM_SET"

# --- Check 3: PCI DSS detection rules ---
echo "Checking PCI DSS detection rules..."

RULES_XML=$(wazuh_exec "cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo ''")

PCI_RULE_COUNT=0
PCI_RULE_HIGH_LEVEL=0

# Look for rules addressing PCI DSS Requirement 10 violation categories
PRIV_ACCESS_RULE=0
AUTH_FAIL_RULE=0
AUDIT_TAMPER_RULE=0
LOGON_RULE=0

if echo "$RULES_XML" | grep -qiE 'pci|cardholder|payment.*card|PCI.DSS|cde\b'; then
    PCI_RULE_COUNT=$((PCI_RULE_COUNT + 1))
fi

if echo "$RULES_XML" | grep -qiE 'privilege.*access|privileged.*user|admin.*access|root.*access|unauthorized.*priv'; then
    PRIV_ACCESS_RULE=1
    PCI_RULE_COUNT=$((PCI_RULE_COUNT + 1))
fi

if echo "$RULES_XML" | grep -qiE 'failed.*auth|auth.*fail|authentication.*failure|brute.*force|multiple.*fail'; then
    AUTH_FAIL_RULE=1
    PCI_RULE_COUNT=$((PCI_RULE_COUNT + 1))
fi

if echo "$RULES_XML" | grep -qiE 'audit.*log.*modif|log.*tamper|log.*delet|audit.*clear|system.*log.*modif'; then
    AUDIT_TAMPER_RULE=1
    PCI_RULE_COUNT=$((PCI_RULE_COUNT + 1))
fi

# Check for any new rule at level >=10 compared to baseline
CURRENT_RULE_COUNT=0
RULE_COUNT_OUT=$(echo "$RULES_XML" | grep -c '<rule id=')
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_RULE_COUNT=$RULE_COUNT_OUT
fi
NEW_RULES=$((CURRENT_RULE_COUNT - INITIAL_RULE_COUNT))
[ "$NEW_RULES" -lt 0 ] && NEW_RULES=0

# Check level of new rules
if echo "$RULES_XML" | grep -qE 'level="(1[0-9]|[2-9][0-9])"'; then
    PCI_RULE_HIGH_LEVEL=1
fi

# For scoring: need at least 2 new rules total covering distinct PCI topics
DISTINCT_PCI_TOPICS=$((PRIV_ACCESS_RULE + AUTH_FAIL_RULE + AUDIT_TAMPER_RULE))
[ "$PCI_RULE_COUNT" -gt 0 ] && [ "$DISTINCT_PCI_TOPICS" -eq 0 ] && DISTINCT_PCI_TOPICS=1

echo "PCI rules: count=$PCI_RULE_COUNT, high_level=$PCI_RULE_HIGH_LEVEL, distinct_topics=$DISTINCT_PCI_TOPICS, new=$NEW_RULES"

# --- Check 4: Compliance evidence report ---
echo "Checking compliance evidence report..."

REPORT_PATH="/home/ga/Desktop/pci_compliance_report.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_AFTER_START=0
REPORT_HAS_PCI_CONTENT=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_PATH" 2>/dev/null || echo "0")
    if ! echo "$REPORT_SIZE" | grep -qE '^[0-9]+$'; then
        REPORT_SIZE=0
    fi
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        REPORT_AFTER_START=1
    fi
    # Check for PCI DSS specific content
    if grep -qiE 'pci|requirement 10|10\.[1-7]|cardholder|audit log|privileged access' "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_PCI_CONTENT=1
    fi
fi
echo "Report: exists=$REPORT_EXISTS, size=$REPORT_SIZE, after_start=$REPORT_AFTER_START, has_pci=$REPORT_HAS_PCI_CONTENT"

# Write result JSON
cat > /tmp/pci_dss_compliance_controls_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "pci_policy_found": ${PCI_POLICY_FOUND},
    "pci_check_count": ${PCI_CHECK_COUNT},
    "email_configured": ${EMAIL_CONFIGURED},
    "email_to_set": ${EMAIL_TO_SET},
    "email_smtp_set": ${EMAIL_SMTP_SET},
    "email_from_set": ${EMAIL_FROM_SET},
    "pci_rule_count": ${PCI_RULE_COUNT},
    "pci_rule_high_level": ${PCI_RULE_HIGH_LEVEL},
    "distinct_pci_topics": ${DISTINCT_PCI_TOPICS},
    "new_rule_count": ${NEW_RULES},
    "current_rule_count": ${CURRENT_RULE_COUNT},
    "initial_rule_count": ${INITIAL_RULE_COUNT},
    "report_exists": ${REPORT_EXISTS},
    "report_size": ${REPORT_SIZE},
    "report_after_start": ${REPORT_AFTER_START},
    "report_has_pci_content": ${REPORT_HAS_PCI_CONTENT}
}
JSONEOF

echo "Result JSON written to /tmp/pci_dss_compliance_controls_result.json"
python3 -m json.tool /tmp/pci_dss_compliance_controls_result.json > /dev/null 2>&1 && echo "JSON valid" || echo "WARNING: JSON may be malformed"

echo "=== Export Complete ==="
