#!/bin/bash
# post_task: Export results for incident_correlation_response
echo "=== Exporting incident_correlation_response Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_AR_COUNT=$(cat /tmp/initial_ar_count 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Desktop/incident_report.txt"

take_screenshot /tmp/task_end_screenshot.png

# === Check 1: Correlation rule with frequency + timeframe attributes ===
CORRELATION_RULE_EXISTS=0
CORRELATION_RULE_LEVEL=0
CORRELATION_RULE_FREQUENCY=0
CORRELATION_RULE_TIMEFRAME=0

CORR_CHECK=$(docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/var/ossec/etc/rules/local_rules.xml')
    root = tree.getroot()
    best_level = 0
    best_freq = 0
    best_time = 0
    found = False
    for rule in root.iter('rule'):
        freq = rule.get('frequency', '')
        timeframe = rule.get('timeframe', '')
        # Rule must have both frequency AND timeframe attributes
        if freq and timeframe:
            try:
                freq_val = int(freq)
                time_val = int(timeframe)
                level = int(rule.get('level', 0))
                if level >= 1:  # Accept any level (we'll score on level separately)
                    found = True
                    if level > best_level:
                        best_level = level
                        best_freq = freq_val
                        best_time = time_val
            except ValueError:
                pass
    print(f'{1 if found else 0},{best_level},{best_freq},{best_time}')
except Exception as e:
    print('0,0,0,0')
" 2>/dev/null || echo "0,0,0,0")

CORRELATION_RULE_EXISTS=$(echo "$CORR_CHECK" | cut -d',' -f1)
CORRELATION_RULE_LEVEL=$(echo "$CORR_CHECK" | cut -d',' -f2)
CORRELATION_RULE_FREQUENCY=$(echo "$CORR_CHECK" | cut -d',' -f3)
CORRELATION_RULE_TIMEFRAME=$(echo "$CORR_CHECK" | cut -d',' -f4)

[ -z "$CORRELATION_RULE_EXISTS" ] && CORRELATION_RULE_EXISTS=0
[ -z "$CORRELATION_RULE_LEVEL" ] && CORRELATION_RULE_LEVEL=0
[ -z "$CORRELATION_RULE_FREQUENCY" ] && CORRELATION_RULE_FREQUENCY=0
[ -z "$CORRELATION_RULE_TIMEFRAME" ] && CORRELATION_RULE_TIMEFRAME=0

# === Check 2: Active response configured in ossec.conf ===
ACTIVE_RESPONSE_CONFIGURED=0

CURRENT_AR_COUNT=$(docker exec "${CONTAINER}" grep -c "<active-response>" \
    /var/ossec/etc/ossec.conf 2>/dev/null)
[ -z "$CURRENT_AR_COUNT" ] && CURRENT_AR_COUNT=0

if [ "$CURRENT_AR_COUNT" -gt "$INITIAL_AR_COUNT" ] 2>/dev/null; then
    ACTIVE_RESPONSE_CONFIGURED=1
fi

# Check host-mounted config as fallback.
# Compare against INITIAL_AR_COUNT to avoid false positives from pre-existing AR entries.
HOST_AR=$(grep -c "<active-response>" \
    /home/ga/wazuh/config/wazuh_cluster/wazuh_manager.conf 2>/dev/null)
[ -z "$HOST_AR" ] && HOST_AR=0
if [ "$HOST_AR" -gt "$INITIAL_AR_COUNT" ] 2>/dev/null; then
    ACTIVE_RESPONSE_CONFIGURED=1
fi

# If current count is equal to initial but > 0, still flag as configured
# (agent may have modified an existing entry rather than adding a new one)
if [ "$CURRENT_AR_COUNT" -gt 0 ] 2>/dev/null; then
    # Check if any active-response entry references a rule_id >= 100000 (custom rule range)
    if docker exec "${CONTAINER}" python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/var/ossec/etc/ossec.conf')
    root = tree.getroot()
    for ar in root.iter('active-response'):
        rule_id_el = ar.find('rules_id')
        if rule_id_el is not None and rule_id_el.text:
            ids = [int(x.strip()) for x in rule_id_el.text.split(',') if x.strip().isdigit()]
            if any(rid >= 100000 for rid in ids):
                print('custom_rule_in_ar')
                exit(0)
    print('no_custom_rule')
except:
    print('error')
" 2>/dev/null | grep -q "custom_rule_in_ar"; then
        ACTIVE_RESPONSE_CONFIGURED=1
    fi
fi

# === Check 3: Incident report file ===
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_AFTER_START=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(wc -c < "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        REPORT_AFTER_START=1
    fi
fi

# Create result JSON
cat > /tmp/incident_correlation_response_result.json << EOF
{
    "task_start": ${TASK_START},
    "correlation_rule_exists": ${CORRELATION_RULE_EXISTS},
    "correlation_rule_level": ${CORRELATION_RULE_LEVEL},
    "correlation_rule_frequency": ${CORRELATION_RULE_FREQUENCY},
    "correlation_rule_timeframe": ${CORRELATION_RULE_TIMEFRAME},
    "active_response_configured": ${ACTIVE_RESPONSE_CONFIGURED},
    "report_exists": ${REPORT_EXISTS},
    "report_size_chars": ${REPORT_SIZE},
    "report_mtime": ${REPORT_MTIME},
    "report_created_after_start": ${REPORT_AFTER_START},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/incident_correlation_response_result.json
echo "=== Export Complete ==="
