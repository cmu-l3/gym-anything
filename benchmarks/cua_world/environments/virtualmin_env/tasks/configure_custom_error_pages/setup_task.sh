#!/bin/bash
echo "=== Setting up configure_custom_error_pages task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempt state
# Remove the errors directory
rm -rf /home/acmecorp/public_html/errors

# Remove ErrorDocument directives from .htaccess if present
if [ -f /home/acmecorp/public_html/.htaccess ]; then
    sed -i '/ErrorDocument/d' /home/acmecorp/public_html/.htaccess
fi

# Remove ErrorDocument directives from Apache config
# Usually located in /etc/apache2/sites-available/acmecorp.test.conf
CONF_FILE=$(grep -l "ServerName acmecorp.test" /etc/apache2/sites-available/*.conf 2>/dev/null | head -1)
if [ -n "$CONF_FILE" ]; then
    sed -i '/ErrorDocument/d' "$CONF_FILE"
fi

# Restart Apache to ensure clean state
systemctl restart apache2

# 2. Ensure Virtualmin is ready and open in Firefox
ensure_virtualmin_ready

# 3. Navigate to the acmecorp.test virtual server dashboard
# We need the numeric ID for acmecorp.test
DOM_ID=$(get_domain_id "acmecorp.test")

if [ -n "$DOM_ID" ]; then
    # Navigate to the virtual server details page
    navigate_to "${VIRTUALMIN_URL}/virtual-server/edit_domain.cgi?dom=${DOM_ID}"
else
    # Fallback to main page if domain lookup fails
    navigate_to "${VIRTUALMIN_URL}/"
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="