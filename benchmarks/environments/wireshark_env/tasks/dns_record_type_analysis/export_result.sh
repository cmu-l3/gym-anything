#!/bin/bash
# Export script for DNS Record Type Analysis task
echo "=== Exporting DNS Record Type Analysis Result ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# Load ground truth
GT_DOMAINS=$(cat /tmp/ground_truth_dns_domains 2>/dev/null || echo "")
GT_TYPE_NAMES=$(cat /tmp/ground_truth_dns_type_names 2>/dev/null || echo "")
GT_TYPE_COUNTS=$(cat /tmp/ground_truth_dns_type_counts 2>/dev/null || echo "")
GT_DNS_SERVERS=$(cat /tmp/ground_truth_dns_servers 2>/dev/null || echo "")
GT_QUERY_COUNT=$(cat /tmp/ground_truth_dns_query_count 2>/dev/null || echo "0")
GT_RESPONSE_COUNT=$(cat /tmp/ground_truth_dns_response_count 2>/dev/null || echo "0")

# Find agent's report
REPORT_FILE=""
for candidate in \
    "/home/ga/Documents/captures/dns_audit_report.txt" \
    "/home/ga/Desktop/dns_audit_report.txt" \
    "/home/ga/dns_audit_report.txt" \
    "/tmp/dns_audit_report.txt"; do
    if [ -f "$candidate" ]; then
        REPORT_FILE="$candidate"
        break
    fi
done

FILE_EXISTS="false"
CONTENT_LENGTH=0
DOMAINS_FOUND=0
DOMAINS_TOTAL=0
TYPES_FOUND=0
TYPES_TOTAL=0
HAS_DNS_SERVER="false"
HAS_QUERY_COUNT="false"
HAS_RESPONSE_COUNT="false"

if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null)
    CONTENT_LENGTH=${#REPORT_CONTENT}
    REPORT_LOWER=$(echo "$REPORT_CONTENT" | tr '[:upper:]' '[:lower:]')

    # Check domains
    DOMAINS_TOTAL=$(echo "$GT_DOMAINS" | grep -c . || echo "0")
    for domain in $GT_DOMAINS; do
        DOMAIN_LOWER=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
        if [ -n "$DOMAIN_LOWER" ] && echo "$REPORT_LOWER" | grep -qF "$DOMAIN_LOWER"; then
            DOMAINS_FOUND=$((DOMAINS_FOUND + 1))
        fi
    done

    # Check record types (case-insensitive)
    TYPES_TOTAL=$(echo "$GT_TYPE_NAMES" | grep -c . || echo "0")
    for rtype in $GT_TYPE_NAMES; do
        RTYPE_LOWER=$(echo "$rtype" | tr '[:upper:]' '[:lower:]')
        RTYPE_UPPER=$(echo "$rtype" | tr '[:lower:]' '[:upper:]')
        if echo "$REPORT_CONTENT" | grep -qE "\b${RTYPE_UPPER}\b|\b${RTYPE_LOWER}\b|\b${rtype}\b"; then
            TYPES_FOUND=$((TYPES_FOUND + 1))
        fi
    done

    # Check DNS server IP
    for server_ip in $GT_DNS_SERVERS; do
        if [ -n "$server_ip" ] && echo "$REPORT_CONTENT" | grep -qF "$server_ip"; then
            HAS_DNS_SERVER="true"
            break
        fi
    done

    # Check query count
    AGENT_QCOUNT=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
        if [ "$num" -ge "$((GT_QUERY_COUNT - 2))" ] 2>/dev/null && [ "$num" -le "$((GT_QUERY_COUNT + 2))" ] 2>/dev/null; then
            echo "$num"
        fi
    done | head -1)
    if [ -n "$AGENT_QCOUNT" ]; then
        HAS_QUERY_COUNT="true"
    fi

    # Check response count
    AGENT_RCOUNT=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
        if [ "$num" -ge "$((GT_RESPONSE_COUNT - 2))" ] 2>/dev/null && [ "$num" -le "$((GT_RESPONSE_COUNT + 2))" ] 2>/dev/null; then
            echo "$num"
        fi
    done | head -1)
    if [ -n "$AGENT_RCOUNT" ]; then
        HAS_RESPONSE_COUNT="true"
    fi
fi

python3 -c "
import json
result = {
    'file_exists': '$FILE_EXISTS' == 'true',
    'content_length': $CONTENT_LENGTH,
    'domains_found': $DOMAINS_FOUND,
    'domains_total': $DOMAINS_TOTAL,
    'types_found': $TYPES_FOUND,
    'types_total': $TYPES_TOTAL,
    'has_dns_server': '$HAS_DNS_SERVER' == 'true',
    'has_query_count': '$HAS_QUERY_COUNT' == 'true',
    'has_response_count': '$HAS_RESPONSE_COUNT' == 'true',
    'ground_truth': {
        'query_count': int('$GT_QUERY_COUNT' or '0'),
        'response_count': int('$GT_RESPONSE_COUNT' or '0')
    }
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print('Result JSON written successfully')
" 2>&1

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
