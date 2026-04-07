#!/bin/bash
echo "=== Setting up Optimize FIM Noise Reduction task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for timestamp verification
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh Manager container is running
if ! docker ps | grep -q "wazuh.manager"; then
    echo "Wazuh manager not running, waiting..."
    sleep 5
fi

# Ensure Firefox is open to the dashboard (context)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Focus terminal or browser? Task is backend config, but we usually focus browser for "desktop" feel
# Let's focus the browser but the agent will likely need to use the terminal
navigate_firefox_to "${WAZUH_URL_CONFIG}"

# Clean up any previous test files inside the container to ensure a clean state
echo "Cleaning up previous test artifacts..."
docker exec wazuh-wazuh.manager-1 rm -f /var/ossec/etc/test_alert.xml /var/ossec/etc/vim_noise.swp 2>/dev/null || true

# Record initial alerts file size/line count to ignore old alerts
INITIAL_ALERTS_LINES=$(docker exec wazuh-wazuh.manager-1 wc -l < /var/ossec/logs/alerts/alerts.json 2>/dev/null || echo "0")
echo "$INITIAL_ALERTS_LINES" > /tmp/initial_alerts_lines.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="