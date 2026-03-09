#!/bin/bash
# pre_task: Setup for configure_email_alerts task
echo "=== Setting up configure_email_alerts task ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Reset ossec.conf to baseline without email configuration
# so the task starts with email_notification=no
echo "Checking current email configuration..."
CURRENT_EMAIL=$(docker exec "${CONTAINER}" grep -A5 "<email_notification>" /var/ossec/etc/ossec.conf 2>/dev/null || echo "not found")
echo "Current email config: $CURRENT_EMAIL"

# Ensure email_notification is set to no in ossec.conf for clean task start
docker exec "${CONTAINER}" bash -c "
    if grep -q '<email_notification>' /var/ossec/etc/ossec.conf; then
        sed -i 's|<email_notification>yes</email_notification>|<email_notification>no</email_notification>|g' /var/ossec/etc/ossec.conf
        sed -i '/<smtp_server>smtp.company/d' /var/ossec/etc/ossec.conf
        sed -i '/<email_to>security-alerts/d' /var/ossec/etc/ossec.conf
        sed -i '/<email_from>wazuh@company/d' /var/ossec/etc/ossec.conf
    fi
" 2>/dev/null && echo "Email alerts reset to disabled state" || echo "WARNING: Could not reset email config"

# Navigate to Wazuh Configuration management page
echo "Opening Wazuh Configuration management page..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3

navigate_firefox_to "${WAZUH_URL_CONFIG}"
sleep 6

take_screenshot /tmp/configure_email_alerts_initial.png
echo "Initial screenshot saved to /tmp/configure_email_alerts_initial.png"

echo "=== configure_email_alerts task setup complete ==="
echo "Task: Configure email alerts in Wazuh"
echo "  smtp_server: smtp.company.internal"
echo "  email_to: security-alerts@company.com"
echo "  email_from: wazuh@company.com"
echo "  email_maxperhour: 12"
echo "Navigate to: Management > Configuration > Email alerts"
