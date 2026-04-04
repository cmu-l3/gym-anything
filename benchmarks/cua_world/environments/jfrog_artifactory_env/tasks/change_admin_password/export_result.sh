#!/bin/bash
echo "=== Exporting change_admin_password results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Verification Probe 1: Does the NEW password work?
echo "Probing new password authentication..."
NEW_PW_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:SecureAdmin2024!" \
    "http://localhost:8082/artifactory/api/system/ping" || echo "000")
echo "Auth with new password: HTTP $NEW_PW_STATUS"

# 3. Verification Probe 2: Does the OLD password fail?
echo "Probing old password authentication..."
OLD_PW_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    "http://localhost:8082/artifactory/api/system/ping" || echo "000")
echo "Auth with old password: HTTP $OLD_PW_STATUS"

# 4. Gather Evidence
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_STATUS=$(cat /tmp/initial_auth_status.txt 2>/dev/null || echo "000")

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 5. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_auth_status": $INITIAL_STATUS,
    "new_password_auth_status": $NEW_PW_STATUS,
    "old_password_auth_status": $OLD_PW_STATUS,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="