#!/bin/bash
set -e
echo "=== Setting up configure_webmin_access task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset Webmin IP access control to default (allow all) to ensure clean state
# Remove 'allow=' and 'deny=' lines from miniserv.conf
sed -i '/^allow=/d' /etc/webmin/miniserv.conf
sed -i '/^deny=/d' /etc/webmin/miniserv.conf
systemctl restart webmin
sleep 3

# 2. Ensure Virtualmin is ready and Firefox is open
ensure_virtualmin_ready

# 3. Navigate to the Webmin tab (system configuration area)
# We'll land the user on the main dashboard, they need to find "Webmin Configuration"
# But to be helpful and reduce noise, we can navigate closer if needed.
# For this task, landing on the main index is fine, but let's switch to the "Webmin" tab view if possible.
# Actually, the default view is fine.
navigate_to "https://localhost:10000/?cat=webmin"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="