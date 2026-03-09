#!/bin/bash
echo "=== Exporting create_readonly_dns_auditor results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if user exists
USER_EXISTS="false"
if grep -q "^dns_auditor:" /etc/webmin/miniserv.users; then
    USER_EXISTS="true"
fi

# 2. Check Global ACL (Modules accessed)
# Line format: username: module1 module2 ...
# We want to see 'bind8' and NOT see dangerous ones like 'useradmin' or 'shell'
# Note: 'system-status' might be there by default, which is fine.
GLOBAL_ACL_LINE=$(grep "^dns_auditor:" /etc/webmin/webmin.acl || echo "")
HAS_BIND_ACCESS="false"
if [[ "$GLOBAL_ACL_LINE" == *"bind8"* ]]; then
    HAS_BIND_ACCESS="true"
fi

# 3. Check Module Specific ACL (Read-only status)
# File: /etc/webmin/bind8/dns_auditor.acl
# We are looking for:
# readonly=1 (Cannot edit zones)
# noconfig=1 (Cannot edit module config)
# stop=0 (Cannot stop server)
BIND_ACL_FILE="/etc/webmin/bind8/dns_auditor.acl"
ACL_READONLY="0"
ACL_NOCONFIG="0"
ACL_STOP="1" # Default is usually 1 (allowed) if not present, we want 0

if [ -f "$BIND_ACL_FILE" ]; then
    ACL_READONLY=$(grep "^readonly=" "$BIND_ACL_FILE" | cut -d= -f2 || echo "0")
    ACL_NOCONFIG=$(grep "^noconfig=" "$BIND_ACL_FILE" | cut -d= -f2 || echo "0")
    # For 'stop', if it's missing, it defaults to allowed usually, but check explicit set
    ACL_STOP=$(grep "^stop=" "$BIND_ACL_FILE" | cut -d= -f2 || echo "1")
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_exists": $USER_EXISTS,
    "global_acl_line": "$(json_escape "$GLOBAL_ACL_LINE")",
    "has_bind_access": $HAS_BIND_ACCESS,
    "bind_acl_file_exists": $([ -f "$BIND_ACL_FILE" ] && echo "true" || echo "false"),
    "acl_readonly": "$ACL_READONLY",
    "acl_noconfig": "$ACL_NOCONFIG",
    "acl_stop": "$ACL_STOP",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="