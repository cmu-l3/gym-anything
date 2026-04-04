#!/bin/bash
echo "=== Exporting modify_server_limits results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Collect Current State Data
# ---------------------------------------------------------------

# Get full domain info
DOMAIN_INFO=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null)

# Extract specific values using grep/sed
# Note: Virtualmin output formats can vary, we grab lines for Python parsing
QUOTA_LINE=$(echo "$DOMAIN_INFO" | grep -i "Server byte quota" || echo "")
BW_LINE=$(echo "$DOMAIN_INFO" | grep -i "Bandwidth limit" || echo "")
MAX_MAIL_LINE=$(echo "$DOMAIN_INFO" | grep -i "Maximum mailboxes" || echo "")
MAX_ALIAS_LINE=$(echo "$DOMAIN_INFO" | grep -i "Maximum aliases" || echo "")
MAX_DB_LINE=$(echo "$DOMAIN_INFO" | grep -i "Maximum databases" || echo "")

# ---------------------------------------------------------------
# Verify Password Change
# ---------------------------------------------------------------
PASSWORD_CHANGED="false"
AUTH_SUCCESS="false"

# Check 1: Hash change
INIT_SHADOW=$(cat /tmp/initial_shadow_entry.txt 2>/dev/null || echo "")
CURR_SHADOW=$(grep "^acmecorp:" /etc/shadow 2>/dev/null || echo "")

if [ "$INIT_SHADOW" != "$CURR_SHADOW" ] && [ -n "$CURR_SHADOW" ]; then
    PASSWORD_CHANGED="true"
fi

# Check 2: Functional Authentication verify
# We use python's crypt module to verify the password against the shadow hash
# This is a robust check running inside the container
VERIFY_AUTH=$(python3 -c "
import crypt, spwd, sys
try:
    user = 'acmecorp'
    password = 'Downgraded2024!'
    shadow_entry = spwd.getspnam(user)
    if crypt.crypt(password, shadow_entry.sp_pwdp) == shadow_entry.sp_pwdp:
        print('true')
    else:
        print('false')
except Exception:
    print('error')
" 2>/dev/null)

if [ "$VERIFY_AUTH" = "true" ]; then
    AUTH_SUCCESS="true"
fi

# ---------------------------------------------------------------
# Create JSON Output
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "raw_quota_line": "$(json_escape "$QUOTA_LINE")",
    "raw_bw_line": "$(json_escape "$BW_LINE")",
    "raw_max_mail_line": "$(json_escape "$MAX_MAIL_LINE")",
    "raw_max_alias_line": "$(json_escape "$MAX_ALIAS_LINE")",
    "raw_max_db_line": "$(json_escape "$MAX_DB_LINE")",
    "password_hash_changed": $PASSWORD_CHANGED,
    "password_auth_success": $AUTH_SUCCESS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="