#!/bin/bash
echo "=== Exporting safety_incident_disciplinary_logging result ==="

source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_final.png ga
sleep 1

# Export the Sentrifugo database to a SQL dump for raw verification
echo "Dumping Sentrifugo database..."
docker exec sentrifugo-db mysqldump -u root -prootpass123 sentrifugo > /tmp/sentrifugo_dump.sql 2>/dev/null

# Verify target strings exist in the database dump
FOUND_MINOR="false"
FOUND_CRITICAL="false"
FOUND_INC1="false"
FOUND_INC2="false"

if grep -qi "OSHA Violation - Minor" /tmp/sentrifugo_dump.sql; then
    FOUND_MINOR="true"
fi

if grep -qi "OSHA Violation - Critical" /tmp/sentrifugo_dump.sql; then
    FOUND_CRITICAL="true"
fi

if grep -qi "high-visibility vest" /tmp/sentrifugo_dump.sql; then
    FOUND_INC1="true"
fi

if grep -qi "lockout/tagout" /tmp/sentrifugo_dump.sql; then
    FOUND_INC2="true"
fi

# Count POST requests in the Apache access log after the TASK START marker
# This proves the agent used the UI rather than injecting SQL directly
POST_COUNT=$(awk '/--- TASK START ---/{flag=1; next} flag && /"POST / {count++} END {print count+0}' /var/log/apache2/sentrifugo_access.log)

# Create JSON result payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "post_count": $POST_COUNT,
    "found_minor_type": $FOUND_MINOR,
    "found_critical_type": $FOUND_CRITICAL,
    "found_incident_1": $FOUND_INC1,
    "found_incident_2": $FOUND_INC2,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported results:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="