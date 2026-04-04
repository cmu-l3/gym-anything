#!/bin/bash
echo "=== Exporting protected directory task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

WEBROOT="/home/acmecorp/public_html"
STAGING_DIR="${WEBROOT}/staging"

# ---------------------------------------------------------------
# 1. Check Configuration Files (.htaccess / .htpasswd)
# ---------------------------------------------------------------
HTACCESS_EXISTS="false"
HTACCESS_CONTENT=""
HTACCESS_MTIME="0"

if [ -f "${STAGING_DIR}/.htaccess" ]; then
    HTACCESS_EXISTS="true"
    HTACCESS_CONTENT=$(cat "${STAGING_DIR}/.htaccess" | base64 -w 0)
    HTACCESS_MTIME=$(stat -c %Y "${STAGING_DIR}/.htaccess" 2>/dev/null || echo "0")
fi

# Find any password file
PASSWD_FILE_FOUND="false"
PASSWD_FILE_MTIME="0"
REVIEWER_FOUND="false"

# Look in common locations
POTENTIAL_PASSWD_FILES=$(find "${WEBROOT}" /etc/apache2 /etc/webmin /home/acmecorp -name ".htpasswd" -o -name "htpasswd" -o -name "*.htpasswd" -o -name "*.auth" 2>/dev/null | head -20)

for pf in $POTENTIAL_PASSWD_FILES; do
    if grep -q "^reviewer:" "$pf" 2>/dev/null; then
        PASSWD_FILE_FOUND="true"
        PASSWD_FILE_MTIME=$(stat -c %Y "$pf" 2>/dev/null || echo "0")
        REVIEWER_FOUND="true"
        break
    fi
done

# Check Apache config for Directory directives (Virtualmin alternative method)
APACHE_CONFIG_HAS_AUTH="false"
for conf in /etc/apache2/sites-available/acmecorp.test.conf /etc/apache2/sites-enabled/acmecorp.test.conf; do
    if [ -f "$conf" ]; then
        if grep -A20 "<Directory.*staging" "$conf" 2>/dev/null | grep -qi "AuthType\s*Basic"; then
            APACHE_CONFIG_HAS_AUTH="true"
            break
        fi
    fi
done

# ---------------------------------------------------------------
# 2. Test HTTP Responses (Functional Verification)
# ---------------------------------------------------------------

# Ensure DNS resolves
grep -q "acmecorp.test" /etc/hosts 2>/dev/null || echo "127.0.0.1 acmecorp.test" >> /etc/hosts

# A: Request WITHOUT credentials
HTTP_NO_AUTH=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "acmecorp.test:80:127.0.0.1" \
    --max-time 5 \
    "http://acmecorp.test/staging/" 2>/dev/null || echo "000")

# B: Request WITH WRONG credentials
HTTP_WRONG_AUTH=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "acmecorp.test:80:127.0.0.1" \
    -u "reviewer:WrongPass123" \
    --max-time 5 \
    "http://acmecorp.test/staging/" 2>/dev/null || echo "000")

# C: Request WITH CORRECT credentials
# Capture body to verify content
HTTP_CORRECT_AUTH=$(curl -s -o /tmp/auth_response_body.html -w "%{http_code}" \
    --resolve "acmecorp.test:80:127.0.0.1" \
    -u "reviewer:SecurePreview2024!" \
    --max-time 5 \
    "http://acmecorp.test/staging/" 2>/dev/null || echo "000")

CONTENT_MATCH="false"
if [ "$HTTP_CORRECT_AUTH" = "200" ]; then
    if grep -qi "AcmeCorp.*Redesign" /tmp/auth_response_body.html; then
        CONTENT_MATCH="true"
    fi
fi

# ---------------------------------------------------------------
# 3. Final Screenshot and JSON Export
# ---------------------------------------------------------------
take_screenshot /tmp/task_final.png

# Initial state check
INITIAL_STATE_VAL=$(cat /tmp/initial_staging_state.txt 2>/dev/null | head -1 || echo "unknown")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_state": "$INITIAL_STATE_VAL",
    "htaccess_exists": $HTACCESS_EXISTS,
    "htaccess_content_b64": "$HTACCESS_CONTENT",
    "htaccess_mtime": $HTACCESS_MTIME,
    "apache_config_has_auth": $APACHE_CONFIG_HAS_AUTH,
    "passwd_file_found": $PASSWD_FILE_FOUND,
    "passwd_file_mtime": $PASSWD_FILE_MTIME,
    "reviewer_user_found": $REVIEWER_FOUND,
    "http_no_auth": "$HTTP_NO_AUTH",
    "http_wrong_auth": "$HTTP_WRONG_AUTH",
    "http_correct_auth": "$HTTP_CORRECT_AUTH",
    "content_match": $CONTENT_MATCH,
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