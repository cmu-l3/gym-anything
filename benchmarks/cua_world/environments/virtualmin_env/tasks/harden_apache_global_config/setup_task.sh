#!/bin/bash
echo "=== Setting up harden_apache_global_config task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Apache is in an INSECURE state (the starting state)
echo "--- Resetting Apache to insecure defaults ---"
CONF_FILE="/etc/apache2/conf-available/security.conf"

# Ensure security.conf is enabled
if [ ! -L "/etc/apache2/conf-enabled/security.conf" ]; then
    a2enconf security > /dev/null 2>&1 || true
fi

# Modify directives to be insecure/verbose
# ServerTokens OS -> reveals version
if grep -q "^ServerTokens" "$CONF_FILE"; then
    sed -i 's/^ServerTokens .*/ServerTokens OS/' "$CONF_FILE"
else
    echo "ServerTokens OS" >> "$CONF_FILE"
fi

# ServerSignature On -> shows footer
if grep -q "^ServerSignature" "$CONF_FILE"; then
    sed -i 's/^ServerSignature .*/ServerSignature On/' "$CONF_FILE"
else
    echo "ServerSignature On" >> "$CONF_FILE"
fi

# TraceEnable On -> allows TRACE method
if grep -q "^TraceEnable" "$CONF_FILE"; then
    sed -i 's/^TraceEnable .*/TraceEnable On/' "$CONF_FILE"
else
    echo "TraceEnable On" >> "$CONF_FILE"
fi

# Reload Apache to apply insecure settings
systemctl reload apache2 || systemctl restart apache2
sleep 2

# Verify initial state (internal check)
INITIAL_TOKEN=$(curl -sI localhost | grep "Server:" || echo "Server: Unknown")
echo "Initial Server Header: $INITIAL_TOKEN"

# 2. Ensure Virtualmin is ready in Firefox
ensure_virtualmin_ready

# Navigate to the Apache Web Server main page to save the agent some clicks
# This is usually under Servers > Apache Web Server
navigate_to "${VIRTUALMIN_URL}/apache/index.cgi"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="