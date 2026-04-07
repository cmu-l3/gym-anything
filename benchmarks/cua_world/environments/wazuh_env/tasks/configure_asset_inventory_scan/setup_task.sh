#!/bin/bash
set -e
echo "=== Setting up configure_asset_inventory_scan task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state: Remove socat if installed
echo "Ensuring socat is NOT installed..."
wazuh_exec apt-get remove -y socat 2>/dev/null || true
wazuh_exec apt-get autoremove -y 2>/dev/null || true

# 3. Ensure clean state: Reset syscollector interval in ossec.conf
# The default is usually 1h or 12h. We'll set it to 1h to ensure it's not 3m.
echo "Resetting syscollector configuration..."
# Using sed to replace the interval inside the syscollector block
# This is a bit complex with sed, so we'll just check if it's already 3m and warn,
# or blindly replace typical patterns.
wazuh_exec sed -i 's|<interval>3m</interval>|<interval>1h</interval>|g' /var/ossec/etc/ossec.conf
wazuh_exec sed -i 's|<interval>180s</interval>|<interval>1h</interval>|g' /var/ossec/etc/ossec.conf

# 4. Restart manager to apply clean state
restart_wazuh_manager

# 5. Remove any previous output files
rm -f /home/ga/socat_inventory.json

# 6. Ensure Dashboard is open (for context, though task is CLI/API focus)
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="