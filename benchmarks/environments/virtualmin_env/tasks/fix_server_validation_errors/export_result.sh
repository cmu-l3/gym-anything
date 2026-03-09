#!/bin/bash
echo "=== Exporting fix_server_validation_errors results ==="

source /workspace/scripts/task_utils.sh

DOMAIN="broken-app.test"
USER="broken-app"
EXPECTED_CONFIG="/etc/apache2/sites-available/${DOMAIN}.conf"
DOCROOT="/home/${USER}/public_html"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. CHECK VALIDATION STATUS
# Run the validation command and capture output/exit code
echo "Running validation check..."
VALIDATION_OUTPUT=$(virtualmin validate-domains --domain "$DOMAIN" 2>&1)
VALIDATION_EXIT_CODE=$?
echo "Validation Exit Code: $VALIDATION_EXIT_CODE"
echo "Validation Output: $VALIDATION_OUTPUT"

# 2. CHECK PERMISSIONS
# public_html should be owned by broken-app:broken-app
ACTUAL_OWNER=$(stat -c '%U:%G' "$DOCROOT" 2>/dev/null || echo "missing")
echo "Current DocRoot Owner: $ACTUAL_OWNER"

PERMISSIONS_FIXED="false"
if [ "$ACTUAL_OWNER" == "${USER}:${USER}" ]; then
    PERMISSIONS_FIXED="true"
fi

# 3. CHECK APACHE CONFIG
# Config file should exist
CONFIG_RESTORED="false"
CONFIG_CONTENT_VALID="false"

if [ -f "$EXPECTED_CONFIG" ]; then
    CONFIG_RESTORED="true"
    # Check if it actually looks like a config for this domain
    if grep -q "ServerName $DOMAIN" "$EXPECTED_CONFIG" || grep -q "ServerName *${DOMAIN}" "$EXPECTED_CONFIG"; then
        CONFIG_CONTENT_VALID="true"
    fi
    
    # Also check if it's enabled (symlinked)
    if [ -L "/etc/apache2/sites-enabled/${DOMAIN}.conf" ]; then
        CONFIG_ENABLED="true"
    else
        CONFIG_ENABLED="false"
    fi
else
    CONFIG_ENABLED="false"
fi

# 4. EXPORT JSON
cat > /tmp/task_result.json << EOF
{
    "validation_exit_code": $VALIDATION_EXIT_CODE,
    "validation_output": "$(json_escape "$VALIDATION_OUTPUT")",
    "permissions_fixed": $PERMISSIONS_FIXED,
    "actual_owner": "$ACTUAL_OWNER",
    "config_restored": $CONFIG_RESTORED,
    "config_enabled": $CONFIG_ENABLED,
    "config_content_valid": $CONFIG_CONTENT_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="