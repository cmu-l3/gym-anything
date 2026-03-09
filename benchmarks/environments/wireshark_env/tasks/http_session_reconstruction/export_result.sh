#!/bin/bash
# Export script for HTTP Session Reconstruction task
echo "=== Exporting HTTP Session Reconstruction Result ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# Load ground truth
GT_URIS=$(cat /tmp/ground_truth_http_uris 2>/dev/null || echo "")
GT_SERVER_IP=$(cat /tmp/ground_truth_http_server_ip 2>/dev/null || echo "")
GT_STATUS_CODES=$(cat /tmp/ground_truth_http_status_codes 2>/dev/null || echo "")
GT_USER_AGENT=$(cat /tmp/ground_truth_http_user_agent 2>/dev/null || echo "")
GT_REQUEST_COUNT=$(cat /tmp/ground_truth_http_request_count 2>/dev/null || echo "0")
GT_HOST=$(cat /tmp/ground_truth_http_host 2>/dev/null || echo "")

# Find agent's report
REPORT_FILE=""
for candidate in \
    "/home/ga/Documents/captures/http_analysis_report.txt" \
    "/home/ga/Desktop/http_analysis_report.txt" \
    "/home/ga/http_analysis_report.txt" \
    "/tmp/http_analysis_report.txt"; do
    if [ -f "$candidate" ]; then
        REPORT_FILE="$candidate"
        break
    fi
done

FILE_EXISTS="false"
CONTENT_LENGTH=0
URIS_FOUND=0
URIS_TOTAL=0
HAS_SERVER_IP="false"
STATUS_CODES_FOUND=0
STATUS_CODES_TOTAL=0
HAS_USER_AGENT="false"
HAS_REQUEST_COUNT="false"

if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null)
    CONTENT_LENGTH=${#REPORT_CONTENT}
    REPORT_LOWER=$(echo "$REPORT_CONTENT" | tr '[:upper:]' '[:lower:]')

    # Check URIs — count how many ground truth URIs appear in the report
    URIS_TOTAL=$(echo "$GT_URIS" | grep -c . || echo "0")
    for uri in $GT_URIS; do
        if [ -n "$uri" ] && echo "$REPORT_CONTENT" | grep -qF "$uri"; then
            URIS_FOUND=$((URIS_FOUND + 1))
        fi
    done

    # Check server IP
    if [ -n "$GT_SERVER_IP" ] && echo "$REPORT_CONTENT" | grep -qF "$GT_SERVER_IP"; then
        HAS_SERVER_IP="true"
    fi

    # Check status codes
    STATUS_CODES_TOTAL=$(echo "$GT_STATUS_CODES" | grep -c . || echo "0")
    for code in $GT_STATUS_CODES; do
        if [ -n "$code" ] && echo "$REPORT_CONTENT" | grep -qF "$code"; then
            STATUS_CODES_FOUND=$((STATUS_CODES_FOUND + 1))
        fi
    done

    # Check User-Agent — look for distinctive parts
    if [ -n "$GT_USER_AGENT" ]; then
        # Extract browser identifier (e.g., "Mozilla", "Chrome", "Firefox")
        UA_LOWER=$(echo "$GT_USER_AGENT" | tr '[:upper:]' '[:lower:]')
        # Check for the full string or key parts
        if echo "$REPORT_LOWER" | grep -qF "$(echo "$UA_LOWER" | head -c 30)"; then
            HAS_USER_AGENT="true"
        fi
        # Also check for browser name keywords
        for browser in "mozilla" "chrome" "firefox" "safari" "wget" "curl" "lynx"; do
            if echo "$UA_LOWER" | grep -q "$browser"; then
                if echo "$REPORT_LOWER" | grep -q "$browser"; then
                    HAS_USER_AGENT="true"
                    break
                fi
            fi
        done
    fi

    # Check request count
    AGENT_COUNT=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
        if [ "$num" -ge "$((GT_REQUEST_COUNT - 2))" ] 2>/dev/null && [ "$num" -le "$((GT_REQUEST_COUNT + 2))" ] 2>/dev/null; then
            echo "$num"
        fi
    done | head -1)
    if [ -n "$AGENT_COUNT" ]; then
        HAS_REQUEST_COUNT="true"
    fi
fi

python3 -c "
import json
result = {
    'file_exists': '$FILE_EXISTS' == 'true',
    'content_length': $CONTENT_LENGTH,
    'uris_found': $URIS_FOUND,
    'uris_total': $URIS_TOTAL,
    'has_server_ip': '$HAS_SERVER_IP' == 'true',
    'status_codes_found': $STATUS_CODES_FOUND,
    'status_codes_total': $STATUS_CODES_TOTAL,
    'has_user_agent': '$HAS_USER_AGENT' == 'true',
    'has_request_count': '$HAS_REQUEST_COUNT' == 'true',
    'ground_truth': {
        'server_ip': '$GT_SERVER_IP',
        'request_count': int('$GT_REQUEST_COUNT' or '0'),
        'host': '$GT_HOST'
    }
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print('Result JSON written successfully')
" 2>&1

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
