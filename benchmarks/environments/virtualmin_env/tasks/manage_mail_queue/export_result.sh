#!/bin/bash
echo "=== Exporting manage_mail_queue task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Inspect Postfix Queue
# valid ways to inspect:
# - postqueue -j (JSON output, best if available)
# - mailq (text parsing)

echo "Inspecting mail queue..."

SPAM_SENDER="marketing@acmecorp.test"
LEGIT_SENDER="support@acmecorp.test"

# Check if postqueue -j works (Postfix >= 3.1)
if postqueue -j > /dev/null 2>&1; then
    # Use jq to parse JSON output
    # Count occurrences of sender in the queue
    REMAINING_SPAM=$(postqueue -j | grep -c "\"sender\": \"$SPAM_SENDER\"")
    REMAINING_LEGIT=$(postqueue -j | grep -c "\"sender\": \"$LEGIT_SENDER\"")
    TOTAL_QUEUE=$(postqueue -j | grep -c "\"queue_name\"") # Approximate count based on JSON structure
else
    # Fallback to mailq text parsing
    # mailq format:
    # ID      Size  Arrival Time       Sender
    # ...
    #                                  Recipient
    REMAINING_SPAM=$(mailq | grep "$SPAM_SENDER" | wc -l)
    REMAINING_LEGIT=$(mailq | grep "$LEGIT_SENDER" | wc -l)
    # Total count (lines starting with ID char)
    TOTAL_QUEUE=$(mailq | grep "^[A-F0-9]" | wc -l)
fi

echo "Remaining Spam: $REMAINING_SPAM"
echo "Remaining Legit: $REMAINING_LEGIT"
echo "Total Queue: $TOTAL_QUEUE"

# 3. Create JSON Result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "remaining_spam_count": $REMAINING_SPAM,
    "remaining_legit_count": $REMAINING_LEGIT,
    "total_queue_count": $TOTAL_QUEUE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="