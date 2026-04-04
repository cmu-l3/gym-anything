#!/bin/bash
echo "=== Exporting DNS Zone Parameters Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Identify zone file location
if [ -f /tmp/zone_file_path.txt ]; then
    ZONE_FILE=$(cat /tmp/zone_file_path.txt)
else
    ZONE_FILE=$(find /var/lib/bind /etc/bind -name "acmecorp.test.hosts" -o -name "acmecorp.test.db" 2>/dev/null | head -1)
fi

# Check if zone file was modified
FILE_MODIFIED="false"
ZONE_CONTENT=""
if [ -f "$ZONE_FILE" ]; then
    ZONE_MTIME=$(stat -c %Y "$ZONE_FILE" 2>/dev/null || echo "0")
    if [ "$ZONE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    # Read content for python verifier (encode slightly to avoid JSON breaking)
    # We will cat it here, python will handle reading it from the struct
    ZONE_CONTENT=$(cat "$ZONE_FILE" | base64 -w 0)
fi

# Check live DNS values using dig
# Format: dig +short returns just the values
# SOA format: mname rname serial refresh retry expire minimum
DIG_OUTPUT=$(dig @localhost acmecorp.test SOA +short 2>/dev/null | tr -d '\n')
DIG_TTL=$(dig @localhost acmecorp.test SOA +noall +answer | grep -v "^;" | head -1 | awk '{print $2}')

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "zone_file_path": "$ZONE_FILE",
    "zone_file_exists": $([ -f "$ZONE_FILE" ] && echo "true" || echo "false"),
    "file_modified_during_task": $FILE_MODIFIED,
    "zone_content_base64": "$ZONE_CONTENT",
    "live_dns_soa": "$DIG_OUTPUT",
    "live_dns_ttl": "$DIG_TTL",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="