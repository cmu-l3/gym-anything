#!/bin/bash
# Export script for Network Baseline Audit task
echo "=== Exporting Network Baseline Audit Result ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# Load ground truth
GT_PROTOCOLS=$(cat /tmp/ground_truth_baseline_protocols 2>/dev/null || echo "")
GT_IPS=$(cat /tmp/ground_truth_baseline_ips 2>/dev/null || echo "")
GT_PORTS=$(cat /tmp/ground_truth_baseline_ports 2>/dev/null || echo "")
GT_RETRANS=$(cat /tmp/ground_truth_baseline_retransmissions 2>/dev/null || echo "0")
GT_TOTAL_PACKETS=$(cat /tmp/ground_truth_baseline_total_packets 2>/dev/null || echo "0")
GT_TOTAL_BYTES=$(cat /tmp/ground_truth_baseline_total_bytes 2>/dev/null || echo "0")

# Find agent's report
REPORT_FILE=""
for candidate in \
    "/home/ga/Documents/captures/baseline_audit_report.txt" \
    "/home/ga/Desktop/baseline_audit_report.txt" \
    "/home/ga/baseline_audit_report.txt" \
    "/tmp/baseline_audit_report.txt"; do
    if [ -f "$candidate" ]; then
        REPORT_FILE="$candidate"
        break
    fi
done

FILE_EXISTS="false"
CONTENT_LENGTH=0
PROTOCOLS_FOUND=0
PROTOCOLS_TOTAL=0
IPS_FOUND=0
IPS_TOTAL=0
PORTS_FOUND=0
PORTS_TOTAL=0
HAS_RETRANS="false"
HAS_TOTAL_PACKETS="false"
HAS_TOTAL_BYTES="false"

if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null)
    CONTENT_LENGTH=${#REPORT_CONTENT}
    REPORT_LOWER=$(echo "$REPORT_CONTENT" | tr '[:upper:]' '[:lower:]')

    # Check protocols — look for key protocol names
    # Focus on high-level protocols the agent should identify
    KEY_PROTOCOLS="eth ethernet ip tcp udp http dns"
    for proto in $KEY_PROTOCOLS; do
        if echo "$GT_PROTOCOLS" | tr '[:upper:]' '[:lower:]' | grep -q "$proto"; then
            PROTOCOLS_TOTAL=$((PROTOCOLS_TOTAL + 1))
            if echo "$REPORT_LOWER" | grep -qE "\b${proto}\b"; then
                PROTOCOLS_FOUND=$((PROTOCOLS_FOUND + 1))
            fi
        fi
    done
    # Also check for less common protocols
    for proto in $GT_PROTOCOLS; do
        proto_lower=$(echo "$proto" | tr '[:upper:]' '[:lower:]')
        if [ ${#proto_lower} -ge 3 ]; then
            case "$proto_lower" in
                eth|ethernet|ip|tcp|udp|http|dns) ;; # already counted
                *)
                    PROTOCOLS_TOTAL=$((PROTOCOLS_TOTAL + 1))
                    if echo "$REPORT_LOWER" | grep -qF "$proto_lower"; then
                        PROTOCOLS_FOUND=$((PROTOCOLS_FOUND + 1))
                    fi
                    ;;
            esac
        fi
    done

    # Check IPs
    IPS_TOTAL=$(echo "$GT_IPS" | grep -c . || echo "0")
    for ip in $GT_IPS; do
        if [ -n "$ip" ] && echo "$REPORT_CONTENT" | grep -qF "$ip"; then
            IPS_FOUND=$((IPS_FOUND + 1))
        fi
    done

    # Check ports — look for key port numbers
    PORTS_TOTAL=$(echo "$GT_PORTS" | grep -c . || echo "0")
    for port in $GT_PORTS; do
        if [ -n "$port" ] && echo "$REPORT_CONTENT" | grep -qP "\b${port}\b"; then
            PORTS_FOUND=$((PORTS_FOUND + 1))
        fi
    done

    # Check retransmission count
    # Allow mentioning "0 retransmissions" or the actual count
    if echo "$REPORT_LOWER" | grep -qE "retransmis"; then
        HAS_RETRANS="true"
    fi
    if [ "$GT_RETRANS" -eq 0 ] 2>/dev/null; then
        # If 0 retransmissions, accept "no retransmissions" or "0 retransmissions"
        if echo "$REPORT_LOWER" | grep -qE "no retransmis|0 retransmis|zero retransmis"; then
            HAS_RETRANS="true"
        fi
    else
        AGENT_RETRANS=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
            if [ "$num" -ge "$((GT_RETRANS - 3))" ] 2>/dev/null && [ "$num" -le "$((GT_RETRANS + 3))" ] 2>/dev/null; then
                echo "$num"
            fi
        done | head -1)
        if [ -n "$AGENT_RETRANS" ]; then
            HAS_RETRANS="true"
        fi
    fi

    # Check total packet count (within ±5%)
    PCT5=$((GT_TOTAL_PACKETS * 5 / 100))
    [ "$PCT5" -lt 3 ] && PCT5=3
    LOW=$((GT_TOTAL_PACKETS - PCT5))
    HIGH=$((GT_TOTAL_PACKETS + PCT5))
    AGENT_PKT=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
        if [ "$num" -ge "$LOW" ] 2>/dev/null && [ "$num" -le "$HIGH" ] 2>/dev/null; then
            echo "$num"
        fi
    done | head -1)
    if [ -n "$AGENT_PKT" ]; then
        HAS_TOTAL_PACKETS="true"
    fi

    # Check total bytes (within ±10%)
    PCT10=$((GT_TOTAL_BYTES * 10 / 100))
    [ "$PCT10" -lt 100 ] && PCT10=100
    BLOW=$((GT_TOTAL_BYTES - PCT10))
    BHIGH=$((GT_TOTAL_BYTES + PCT10))
    AGENT_BYTES=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
        if [ "$num" -ge "$BLOW" ] 2>/dev/null && [ "$num" -le "$BHIGH" ] 2>/dev/null; then
            echo "$num"
        fi
    done | head -1)
    if [ -n "$AGENT_BYTES" ]; then
        HAS_TOTAL_BYTES="true"
    fi
fi

python3 -c "
import json
result = {
    'file_exists': '$FILE_EXISTS' == 'true',
    'content_length': $CONTENT_LENGTH,
    'protocols_found': $PROTOCOLS_FOUND,
    'protocols_total': $PROTOCOLS_TOTAL,
    'ips_found': $IPS_FOUND,
    'ips_total': $IPS_TOTAL,
    'ports_found': $PORTS_FOUND,
    'ports_total': $PORTS_TOTAL,
    'has_retrans': '$HAS_RETRANS' == 'true',
    'has_total_packets': '$HAS_TOTAL_PACKETS' == 'true',
    'has_total_bytes': '$HAS_TOTAL_BYTES' == 'true',
    'ground_truth': {
        'retransmissions': int('$GT_RETRANS' or '0'),
        'total_packets': int('$GT_TOTAL_PACKETS' or '0'),
        'total_bytes': int('$GT_TOTAL_BYTES' or '0')
    }
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print('Result JSON written successfully')
" 2>&1

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
