#!/bin/bash
echo "=== Setting up configure_service_watchdog task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure MariaDB is running initially
systemctl start mariadb 2>/dev/null || true

# 2. Reset System and Server Status configuration to a clean state
# This ensures we don't have pre-existing monitors or enabled scheduling
CONFIG_DIR="/etc/webmin/status"
mkdir -p "$CONFIG_DIR"

# Disable scheduled monitoring in main config
if [ -f "$CONFIG_DIR/config" ]; then
    sed -i 's/^sched_mode=1/sched_mode=0/' "$CONFIG_DIR/config"
    # Ensure sched_int is not 5 initially to prevent false positives
    sed -i 's/^sched_int=5/sched_int=60/' "$CONFIG_DIR/config"
else
    echo "sched_mode=0" > "$CONFIG_DIR/config"
    echo "sched_int=60" >> "$CONFIG_DIR/config"
fi

# Remove any existing MySQL monitors to ensure agent creates a new one
# Webmin stores monitors as numbered .serv files (e.g., 1.serv, 2.serv)
# We look for files containing "type=mysql" and remove them
grep -l "type=mysql" "$CONFIG_DIR"/*.serv 2>/dev/null | xargs rm -f 2>/dev/null || true

# 3. Reload Webmin to apply config changes? 
# Webmin usually reads config on the fly, but restarting ensures UI reflects state
systemctl restart webmin

# 4. Prepare Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to the System and Server Status page
# URL: https://localhost:10000/status/index.cgi
navigate_to "https://localhost:10000/status/index.cgi"
sleep 5

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="