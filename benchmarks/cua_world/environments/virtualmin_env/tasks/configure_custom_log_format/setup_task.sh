#!/bin/bash
echo "=== Setting up configure_custom_log_format task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up Global Config (apache2.conf)
# Remove any existing LogFormat lines with the nickname 'latency_trace'
echo "Cleaning global Apache config..."
sed -i '/LogFormat.*latency_trace/d' /etc/apache2/apache2.conf

# 2. Clean up Virtual Host Config (acmecorp.test.conf)
# Revert CustomLog to use 'combined' or 'default'
echo "Cleaning virtual host config..."
VHOST_CONFIG=$(find /etc/apache2/sites-available -name "*acmecorp.test.conf" | head -1)

if [ -f "$VHOST_CONFIG" ]; then
    # Replace any CustomLog line using latency_trace with combined
    sed -i 's/CustomLog.*latency_trace/CustomLog ${APACHE_LOG_DIR}\/acmecorp.test_access_log combined/' "$VHOST_CONFIG"
    # Ensure it uses combined if it was something else crazy, or just ensure a standard line exists
    if ! grep -q "CustomLog" "$VHOST_CONFIG"; then
         # Insert if missing (unlikely in this env)
         sed -i '/<\/VirtualHost>/i \tCustomLog ${APACHE_LOG_DIR}/acmecorp.test_access_log combined' "$VHOST_CONFIG"
    fi
fi

# 3. Apply changes (Restart Apache)
echo "Restarting Apache..."
systemctl restart apache2
sleep 3

# 4. Prepare Browser
echo "Launching Virtualmin..."
ensure_virtualmin_ready

# Navigate to Apache Webserver module to save the agent some clicks
# Page: Global Configuration -> Log Files? Or just the module index.
# Module index is safe.
navigate_to "https://localhost:10000/apache/index.cgi"
sleep 5

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="