#!/bin/bash
# Export script for ransomware_detection_playbook
# Extracts all verification data after the agent has completed (or attempted) the task.

echo "=== Exporting ransomware_detection_playbook Result ==="

source /workspace/scripts/task_utils.sh

if ! type wazuh_exec &>/dev/null; then
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")
INITIAL_AR_COUNT=$(cat /tmp/initial_ar_count 2>/dev/null || echo "0")
INITIAL_FIM_COUNT=$(cat /tmp/initial_fim_count 2>/dev/null || echo "0")

echo "Task start: $TASK_START"

# --- Check 1: FIM on critical paths ---
echo "Checking FIM configuration..."

OSSEC_CONF=$(wazuh_exec "cat /var/ossec/etc/ossec.conf 2>/dev/null || echo ''")
GROUP_AGENT_CONFS=$(wazuh_exec "find /var/ossec/etc/shared -name 'agent.conf' -exec cat {} \; 2>/dev/null || echo ''")
ALL_CONFIGS="${OSSEC_CONF}${GROUP_AGENT_CONFS}"

FIM_PATHS=0
CHECKED_PATHS=""
for path in "/home" "/etc" "/var/www" "/var/backup" "/opt" "/srv" "/root" "/var/log" "/usr/bin" "/usr/sbin"; do
    if echo "$ALL_CONFIGS" | grep -qE "<directories[^>]*>[^<]*${path}"; then
        FIM_PATHS=$((FIM_PATHS + 1))
        CHECKED_PATHS="${CHECKED_PATHS} ${path}"
    fi
done
echo "FIM paths found: $FIM_PATHS ($CHECKED_PATHS)"

# --- Check 2: Ransomware detection rule ---
echo "Checking for ransomware detection rules..."

RULES_XML=$(wazuh_exec "cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo ''")

RANSOM_RULE_FOUND=0
RANSOM_RULE_LEVEL=0
if echo "$RULES_XML" | grep -qiE "vssadmin|shadow.*delet|shadow.*copy|\.encrypted|\.locked|\.crypto|\.WNCRY|\.enc|ransom|T1490|T1486|inhibit.*recover|mass.*file|encrypt.*file"; then
    RANSOM_RULE_FOUND=1
    # Extract the level attribute from the matching rule block
    LEVEL_OUT=$(echo "$RULES_XML" | grep -B5 -A10 -iE "vssadmin|shadow.*delet|shadow.*copy|\.encrypted|\.locked|\.crypto|ransom|T1490|T1486" | grep -oE 'level="[0-9]+"' | head -1 | grep -oE '[0-9]+')
    if echo "$LEVEL_OUT" | grep -qE '^[0-9]+$'; then
        RANSOM_RULE_LEVEL=$LEVEL_OUT
    fi
fi
echo "Ransomware rule found: $RANSOM_RULE_FOUND (level: $RANSOM_RULE_LEVEL)"

# --- Check 3: Frequency correlation rule ---
echo "Checking for frequency correlation rule..."

CORRELATION_FOUND=0
CORRELATION_FREQ=0
CORRELATION_TIMEFRAME=0

if echo "$RULES_XML" | grep -qE 'frequency="[0-9]+"'; then
    CORRELATION_FOUND=1
    FREQ_OUT=$(echo "$RULES_XML" | grep -oE 'frequency="[0-9]+"' | head -1 | grep -oE '[0-9]+')
    if echo "$FREQ_OUT" | grep -qE '^[0-9]+$'; then
        CORRELATION_FREQ=$FREQ_OUT
    fi
    # Also verify timeframe attribute exists (required for true correlation)
    if echo "$RULES_XML" | grep -qE 'timeframe="[0-9]+"'; then
        TIMEFRAME_OUT=$(echo "$RULES_XML" | grep -oE 'timeframe="[0-9]+"' | head -1 | grep -oE '[0-9]+')
        if echo "$TIMEFRAME_OUT" | grep -qE '^[0-9]+$'; then
            CORRELATION_TIMEFRAME=$TIMEFRAME_OUT
        fi
    fi
fi
echo "Correlation rule: found=$CORRELATION_FOUND, freq=$CORRELATION_FREQ, timeframe=$CORRELATION_TIMEFRAME"

# --- Check 4: Active response ---
echo "Checking active response configuration..."

AR_CONFIGURED=0
AR_COUNT=0
if echo "$OSSEC_CONF" | grep -q "<active-response>"; then
    AR_CONFIGURED=1
    AR_COUNT_OUT=$(echo "$OSSEC_CONF" | grep -c "<active-response>")
    if echo "$AR_COUNT_OUT" | grep -qE '^[0-9]+$'; then
        AR_COUNT=$AR_COUNT_OUT
    fi
fi
echo "Active response: configured=$AR_CONFIGURED, count=$AR_COUNT"

# --- Check 5: Incident response playbook ---
echo "Checking for incident response playbook..."

PLAYBOOK_PATH="/home/ga/Desktop/ransomware_playbook.txt"
PLAYBOOK_EXISTS=0
PLAYBOOK_SIZE=0
PLAYBOOK_AFTER_START=0

if [ -f "$PLAYBOOK_PATH" ]; then
    PLAYBOOK_EXISTS=1
    PLAYBOOK_SIZE=$(wc -c < "$PLAYBOOK_PATH" 2>/dev/null || echo "0")
    # Guard against non-numeric
    if ! echo "$PLAYBOOK_SIZE" | grep -qE '^[0-9]+$'; then
        PLAYBOOK_SIZE=0
    fi
    PLAYBOOK_MTIME=$(stat -c %Y "$PLAYBOOK_PATH" 2>/dev/null || echo "0")
    if [ "$PLAYBOOK_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        PLAYBOOK_AFTER_START=1
    fi
fi
echo "Playbook: exists=$PLAYBOOK_EXISTS, size=$PLAYBOOK_SIZE, after_start=$PLAYBOOK_AFTER_START"

# --- Current rule count ---
CURRENT_RULE_COUNT=0
RULE_COUNT_OUT=$(echo "$RULES_XML" | grep -c '<rule id=')
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_RULE_COUNT=$RULE_COUNT_OUT
fi

# --- Write result JSON ---
cat > /tmp/ransomware_detection_playbook_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "fim_path_count": ${FIM_PATHS},
    "ransomware_rule_found": ${RANSOM_RULE_FOUND},
    "ransomware_rule_level": ${RANSOM_RULE_LEVEL},
    "correlation_found": ${CORRELATION_FOUND},
    "correlation_frequency": ${CORRELATION_FREQ},
    "correlation_timeframe": ${CORRELATION_TIMEFRAME},
    "ar_configured": ${AR_CONFIGURED},
    "ar_count": ${AR_COUNT},
    "playbook_exists": ${PLAYBOOK_EXISTS},
    "playbook_size": ${PLAYBOOK_SIZE},
    "playbook_after_start": ${PLAYBOOK_AFTER_START},
    "current_rule_count": ${CURRENT_RULE_COUNT},
    "initial_rule_count": ${INITIAL_RULE_COUNT}
}
JSONEOF

echo "Result JSON written to /tmp/ransomware_detection_playbook_result.json"
python3 -m json.tool /tmp/ransomware_detection_playbook_result.json > /dev/null 2>&1 && echo "JSON is valid" || echo "WARNING: JSON may be malformed"

echo "=== Export Complete ==="
