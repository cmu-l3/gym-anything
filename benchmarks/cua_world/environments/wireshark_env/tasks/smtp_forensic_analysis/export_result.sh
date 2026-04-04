#!/bin/bash
# Export script for SMTP Forensic Analysis task
echo "=== Exporting SMTP Forensic Analysis Result ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load ground truth
GT_SENDER=$(cat /tmp/ground_truth_smtp_sender 2>/dev/null || echo "")
GT_RECIPIENT=$(cat /tmp/ground_truth_smtp_recipient 2>/dev/null || echo "")
GT_SUBJECT=$(cat /tmp/ground_truth_smtp_subject 2>/dev/null || echo "")
GT_BANNER=$(cat /tmp/ground_truth_smtp_banner 2>/dev/null || echo "")
GT_SMTP_COUNT=$(cat /tmp/ground_truth_smtp_count 2>/dev/null || echo "0")

# Search for the agent's report file
REPORT_FILE=""
for candidate in \
    "/home/ga/Documents/captures/smtp_forensic_report.txt" \
    "/home/ga/Desktop/smtp_forensic_report.txt" \
    "/home/ga/smtp_forensic_report.txt" \
    "/tmp/smtp_forensic_report.txt"; do
    if [ -f "$candidate" ]; then
        REPORT_FILE="$candidate"
        break
    fi
done

FILE_EXISTS="false"
REPORT_CONTENT=""
HAS_SENDER="false"
HAS_RECIPIENT="false"
HAS_SUBJECT="false"
HAS_BANNER="false"
HAS_SMTP_COUNT="false"
CONTENT_LENGTH=0

if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null)
    CONTENT_LENGTH=${#REPORT_CONTENT}
    REPORT_LOWER=$(echo "$REPORT_CONTENT" | tr '[:upper:]' '[:lower:]')

    # Check for sender email — extract email-like patterns from ground truth
    # Parse email from angle brackets or bare format
    SENDER_EMAIL=$(echo "$GT_SENDER" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)
    if [ -n "$SENDER_EMAIL" ]; then
        SENDER_LOWER=$(echo "$SENDER_EMAIL" | tr '[:upper:]' '[:lower:]')
        if echo "$REPORT_LOWER" | grep -qF "$SENDER_LOWER"; then
            HAS_SENDER="true"
        fi
    fi

    # Check for recipient email
    RECIPIENT_EMAIL=$(echo "$GT_RECIPIENT" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)
    if [ -n "$RECIPIENT_EMAIL" ]; then
        RECIPIENT_LOWER=$(echo "$RECIPIENT_EMAIL" | tr '[:upper:]' '[:lower:]')
        if echo "$REPORT_LOWER" | grep -qF "$RECIPIENT_LOWER"; then
            HAS_RECIPIENT="true"
        fi
    fi

    # Check for subject line (at least 3-word match)
    if [ -n "$GT_SUBJECT" ]; then
        SUBJECT_LOWER=$(echo "$GT_SUBJECT" | tr '[:upper:]' '[:lower:]')
        # Check if subject text appears in report (flexible matching)
        FIRST_WORDS=$(echo "$SUBJECT_LOWER" | awk '{for(i=1;i<=3&&i<=NF;i++) printf $i" "; print ""}' | xargs)
        if echo "$REPORT_LOWER" | grep -qF "$FIRST_WORDS"; then
            HAS_SUBJECT="true"
        elif echo "$REPORT_LOWER" | grep -qiF "$GT_SUBJECT"; then
            HAS_SUBJECT="true"
        fi
    fi

    # Check for server banner keywords
    if [ -n "$GT_BANNER" ]; then
        BANNER_LOWER=$(echo "$GT_BANNER" | tr '[:upper:]' '[:lower:]')
        # Extract server software name (first meaningful word)
        BANNER_KEY=$(echo "$BANNER_LOWER" | grep -oP '\b[a-z]+\b' | head -1)
        if [ -n "$BANNER_KEY" ] && echo "$REPORT_LOWER" | grep -qF "$BANNER_KEY"; then
            HAS_BANNER="true"
        fi
        # Also check for "220" greeting code mention
        if echo "$REPORT_CONTENT" | grep -q "220"; then
            HAS_BANNER="true"
        fi
    fi

    # Check for SMTP packet count (within ±5)
    AGENT_COUNT=$(echo "$REPORT_CONTENT" | grep -oP '\b[0-9]+\b' | while read num; do
        if [ "$num" -ge "$((GT_SMTP_COUNT - 5))" ] 2>/dev/null && [ "$num" -le "$((GT_SMTP_COUNT + 5))" ] 2>/dev/null; then
            echo "$num"
        fi
    done | head -1)
    if [ -n "$AGENT_COUNT" ]; then
        HAS_SMTP_COUNT="true"
    fi
fi

# Create result JSON
python3 -c "
import json
result = {
    'file_exists': '$FILE_EXISTS' == 'true',
    'content_length': $CONTENT_LENGTH,
    'has_sender': '$HAS_SENDER' == 'true',
    'has_recipient': '$HAS_RECIPIENT' == 'true',
    'has_subject': '$HAS_SUBJECT' == 'true',
    'has_banner': '$HAS_BANNER' == 'true',
    'has_smtp_count': '$HAS_SMTP_COUNT' == 'true',
    'ground_truth': {
        'sender': '''$GT_SENDER''',
        'recipient': '''$GT_RECIPIENT''',
        'subject': '''$GT_SUBJECT''',
        'banner': '''$GT_BANNER''',
        'smtp_count': int('$GT_SMTP_COUNT' or '0')
    }
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print('Result JSON written successfully')
" 2>&1

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
