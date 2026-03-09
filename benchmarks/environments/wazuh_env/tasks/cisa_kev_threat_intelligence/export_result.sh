#!/bin/bash
# Export script for cisa_kev_threat_intelligence
# Checks CDB list with CVEs, detection rules with CDB lookup, vuln detector, and report.

echo "=== Exporting cisa_kev_threat_intelligence Result ==="

source /workspace/scripts/task_utils.sh

if ! type wazuh_exec &>/dev/null; then
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_CDB_COUNT=$(cat /tmp/initial_cdb_count 2>/dev/null || echo "0")
INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")
INITIAL_VULN_DETECTOR=$(cat /tmp/initial_vuln_detector 2>/dev/null || echo "0")

echo "Task start: $TASK_START"

# --- Check 1: CDB list with CVE IDs ---
echo "Checking CDB lists for CVE entries..."

CDB_CVE_FOUND=0
CDB_CVE_COUNT=0
CDB_CVE_FILE=""

# Check all CDB list files for CVE-format entries
CDB_FILES=$(wazuh_exec "ls /var/ossec/etc/lists/ 2>/dev/null || echo ''")
for cdb_file in $CDB_FILES; do
    CONTENT=$(wazuh_exec "cat /var/ossec/etc/lists/${cdb_file} 2>/dev/null || echo ''")
    # CVE format: CVE-YYYY-NNNNN (case-insensitive, with or without trailing colon)
    CVE_LINES=$(echo "$CONTENT" | grep -ciE '^CVE-[0-9]{4}-[0-9]+')
    if [ "$CVE_LINES" -gt 0 ] 2>/dev/null; then
        CDB_CVE_FOUND=1
        CDB_CVE_COUNT=$((CDB_CVE_COUNT + CVE_LINES))
        CDB_CVE_FILE="$cdb_file"
        echo "  Found CVE entries in CDB list: $cdb_file ($CVE_LINES entries)"
    fi
done
echo "CDB CVE list: found=$CDB_CVE_FOUND, total_entries=$CDB_CVE_COUNT, file=$CDB_CVE_FILE"

# --- Check 2: Detection rule using CDB list lookup ---
echo "Checking for rules with CDB list lookup..."

RULES_XML=$(wazuh_exec "cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo ''")

RULE_WITH_CDB=0
CDB_RULE_REFERENCES_KEV=0

if echo "$RULES_XML" | grep -q '<list'; then
    RULE_WITH_CDB=1
    # Check if the list reference points to a CVE/KEV list
    if echo "$RULES_XML" | grep -iE '<list[^>]*>.*kev|<list[^>]*>.*cve|<list[^>]*>.*known.*exploit'; then
        CDB_RULE_REFERENCES_KEV=1
    fi
    # Also count if any list element references a file that exists as a CDB
    if [ -n "$CDB_CVE_FILE" ] && echo "$RULES_XML" | grep -q "$CDB_CVE_FILE"; then
        CDB_RULE_REFERENCES_KEV=1
    fi
fi

CURRENT_RULE_COUNT=0
RULE_COUNT_OUT=$(echo "$RULES_XML" | grep -c '<rule id=')
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    CURRENT_RULE_COUNT=$RULE_COUNT_OUT
fi
NEW_RULES=$((CURRENT_RULE_COUNT - INITIAL_RULE_COUNT))
[ "$NEW_RULES" -lt 0 ] && NEW_RULES=0

echo "CDB rule: rule_with_list=$RULE_WITH_CDB, references_kev=$CDB_RULE_REFERENCES_KEV, new_rules=$NEW_RULES"

# --- Check 3: Vulnerability detection module in ossec.conf ---
echo "Checking vulnerability detection configuration..."

OSSEC_CONF=$(wazuh_exec "cat /var/ossec/etc/ossec.conf 2>/dev/null || echo ''")

VULN_DETECTOR_ENABLED=0
SYSCOLLECTOR_ENABLED=0

if echo "$OSSEC_CONF" | grep -qE 'vulnerability.detector|vulnerability-detector'; then
    VULN_DETECTOR_ENABLED=1
fi
if echo "$OSSEC_CONF" | grep -qE 'wodle.*syscollector|syscollector'; then
    SYSCOLLECTOR_ENABLED=1
fi

# Check if it was enabled after task start (not just pre-existing)
VULN_DETECTOR_IS_NEW=0
if [ "$VULN_DETECTOR_ENABLED" -eq 1 ] && [ "$INITIAL_VULN_DETECTOR" -eq 0 ]; then
    VULN_DETECTOR_IS_NEW=1
elif [ "$VULN_DETECTOR_ENABLED" -eq 1 ]; then
    # Was already there but agent may have modified/enabled it explicitly
    VULN_DETECTOR_IS_NEW=0
fi

echo "Vuln detector: enabled=$VULN_DETECTOR_ENABLED, syscollector=$SYSCOLLECTOR_ENABLED, newly_configured=$VULN_DETECTOR_IS_NEW"

# Also check ossec.conf for any explicit vuln-detector wodle entries
VULN_WODLE=0
if echo "$OSSEC_CONF" | grep -qE '<wodle name="vulnerability-detector"'; then
    VULN_WODLE=1
fi
echo "Vulnerability-detector wodle: $VULN_WODLE"

# --- Check 4: Threat intelligence integration report ---
echo "Checking integration report..."

REPORT_PATH="/home/ga/Desktop/kev_integration_report.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_AFTER_START=0
REPORT_HAS_CISA=0
REPORT_HAS_CVE=0

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
    if grep -qiE 'cisa|known.*exploit|kev\b' "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_CISA=1
    fi
    if grep -qiE 'CVE-[0-9]{4}-[0-9]+|cdb.*list|lookup.*list|threat.*intel' "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_CVE=1
    fi
fi
echo "Report: exists=$REPORT_EXISTS, size=$REPORT_SIZE, after_start=$REPORT_AFTER_START, has_cisa=$REPORT_HAS_CISA, has_cve=$REPORT_HAS_CVE"

# Write result JSON
cat > /tmp/cisa_kev_threat_intelligence_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "cdb_cve_found": ${CDB_CVE_FOUND},
    "cdb_cve_count": ${CDB_CVE_COUNT},
    "rule_with_cdb_lookup": ${RULE_WITH_CDB},
    "cdb_rule_references_kev": ${CDB_RULE_REFERENCES_KEV},
    "new_rule_count": ${NEW_RULES},
    "current_rule_count": ${CURRENT_RULE_COUNT},
    "vuln_detector_enabled": ${VULN_DETECTOR_ENABLED},
    "vuln_detector_wodle": ${VULN_WODLE},
    "syscollector_enabled": ${SYSCOLLECTOR_ENABLED},
    "vuln_detector_newly_configured": ${VULN_DETECTOR_IS_NEW},
    "initial_vuln_detector": ${INITIAL_VULN_DETECTOR},
    "report_exists": ${REPORT_EXISTS},
    "report_size": ${REPORT_SIZE},
    "report_after_start": ${REPORT_AFTER_START},
    "report_has_cisa_reference": ${REPORT_HAS_CISA},
    "report_has_cve_content": ${REPORT_HAS_CVE},
    "initial_cdb_count": ${INITIAL_CDB_COUNT},
    "initial_rule_count": ${INITIAL_RULE_COUNT}
}
JSONEOF

echo "Result JSON written to /tmp/cisa_kev_threat_intelligence_result.json"
python3 -m json.tool /tmp/cisa_kev_threat_intelligence_result.json > /dev/null 2>&1 && echo "JSON valid" || echo "WARNING: JSON may be malformed"

echo "=== Export Complete ==="
