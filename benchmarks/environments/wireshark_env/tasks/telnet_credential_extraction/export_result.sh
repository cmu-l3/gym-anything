#!/bin/bash
# Export script for Telnet Credential Extraction task
echo "=== Exporting Telnet Credential Extraction Result ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# Load ground truth
GT_USERNAME=$(cat /tmp/ground_truth_telnet_username 2>/dev/null || echo "")
GT_PASSWORD=$(cat /tmp/ground_truth_telnet_password 2>/dev/null || echo "")
GT_BANNER=$(cat /tmp/ground_truth_telnet_banner 2>/dev/null || echo "")
GT_COMMANDS=$(cat /tmp/ground_truth_telnet_commands 2>/dev/null || echo "")
GT_TELNET_COUNT=$(cat /tmp/ground_truth_telnet_count 2>/dev/null || echo "0")
GT_STREAM=$(cat /tmp/ground_truth_telnet_stream 2>/dev/null || echo "")

# Find agent's report
REPORT_FILE=""
for candidate in \
    "/home/ga/Documents/captures/telnet_incident_report.txt" \
    "/home/ga/Desktop/telnet_incident_report.txt" \
    "/home/ga/telnet_incident_report.txt" \
    "/tmp/telnet_incident_report.txt"; do
    if [ -f "$candidate" ]; then
        REPORT_FILE="$candidate"
        break
    fi
done

FILE_EXISTS="false"
CONTENT_LENGTH=0
HAS_USERNAME="false"
HAS_PASSWORD="false"
HAS_BANNER="false"
HAS_COMMANDS="false"
HAS_TELNET_COUNT="false"
COMMANDS_FOUND=0

if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null)
    CONTENT_LENGTH=${#REPORT_CONTENT}
    REPORT_LOWER=$(echo "$REPORT_CONTENT" | tr '[:upper:]' '[:lower:]')

    # Check username — try exact match, then partial
    if [ -n "$GT_USERNAME" ]; then
        GT_USER_LOWER=$(echo "$GT_USERNAME" | tr '[:upper:]' '[:lower:]')
        if echo "$REPORT_LOWER" | grep -qF "$GT_USER_LOWER"; then
            HAS_USERNAME="true"
        fi
    fi

    # Check password
    if [ -n "$GT_PASSWORD" ]; then
        GT_PASS_LOWER=$(echo "$GT_PASSWORD" | tr '[:upper:]' '[:lower:]')
        if echo "$REPORT_LOWER" | grep -qF "$GT_PASS_LOWER"; then
            HAS_PASSWORD="true"
        fi
    fi

    # Check banner/OS keywords
    if [ -n "$GT_BANNER" ]; then
        # Extract meaningful keywords from banner
        BANNER_WORDS=$(echo "$GT_BANNER" | tr '[:upper:]' '[:lower:]' | grep -oP '\b[a-z]{3,}\b' | sort -u)
        for word in $BANNER_WORDS; do
            if echo "$REPORT_LOWER" | grep -qF "$word"; then
                HAS_BANNER="true"
                break
            fi
        done
    fi
    # Also check for common OS indicators from the stream
    for os_term in "linux" "unix" "bsd" "sunos" "solaris" "openbsd" "freebsd"; do
        if echo "$GT_STREAM" | tr '[:upper:]' '[:lower:]' | grep -q "$os_term"; then
            if echo "$REPORT_LOWER" | grep -q "$os_term"; then
                HAS_BANNER="true"
                break
            fi
        fi
    done

    # Check for commands — look for command-like lines in the report
    # Extract known commands from the stream
    GT_CMD_WORDS=$(echo "$GT_COMMANDS" | grep -oP '^\S+' | sort -u)
    for cmd in $GT_CMD_WORDS; do
        CMD_LOWER=$(echo "$cmd" | tr '[:upper:]' '[:lower:]')
        if echo "$REPORT_LOWER" | grep -qF "$CMD_LOWER"; then
            COMMANDS_FOUND=$((COMMANDS_FOUND + 1))
        fi
    done
    if [ "$COMMANDS_FOUND" -ge 2 ]; then
        HAS_COMMANDS="true"
    elif [ "$COMMANDS_FOUND" -ge 1 ]; then
        HAS_COMMANDS="partial"
    fi

    # Check telnet packet count
    AGENT_COUNT=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
        if [ "$num" -ge "$((GT_TELNET_COUNT - 10))" ] 2>/dev/null && [ "$num" -le "$((GT_TELNET_COUNT + 10))" ] 2>/dev/null; then
            echo "$num"
        fi
    done | head -1)
    if [ -n "$AGENT_COUNT" ]; then
        HAS_TELNET_COUNT="true"
    fi
fi

python3 -c "
import json
result = {
    'file_exists': '$FILE_EXISTS' == 'true',
    'content_length': $CONTENT_LENGTH,
    'has_username': '$HAS_USERNAME' == 'true',
    'has_password': '$HAS_PASSWORD' == 'true',
    'has_banner': '$HAS_BANNER' == 'true',
    'has_commands': '$HAS_COMMANDS',
    'commands_found': $COMMANDS_FOUND,
    'has_telnet_count': '$HAS_TELNET_COUNT' == 'true',
    'ground_truth': {
        'username': '''$(cat /tmp/ground_truth_telnet_username 2>/dev/null)''',
        'telnet_count': int('$GT_TELNET_COUNT' or '0')
    }
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print('Result JSON written successfully')
" 2>&1

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
