#!/bin/bash
echo "=== Setting up configure_smtp_relay task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset Postfix to a known clean state (no relay)
echo "Resetting Postfix configuration..."
postconf -e relayhost=
postconf -e smtp_sasl_auth_enable=no
postconf -e smtp_sasl_password_maps=
postconf -e smtp_sasl_security_options=noanonymous

# Remove any existing SASL password maps
rm -f /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

# Reload Postfix
systemctl reload postfix 2>/dev/null || systemctl start postfix

# 2. Ensure Virtualmin/Webmin is ready
ensure_virtualmin_ready
sleep 2

# 3. Navigate directly to the Postfix Mail Server module to save navigation time
# This helps focus the task on the configuration logic rather than just finding the menu
echo "Navigating to Postfix module..."
navigate_to "https://localhost:10000/postfix/index.cgi"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="