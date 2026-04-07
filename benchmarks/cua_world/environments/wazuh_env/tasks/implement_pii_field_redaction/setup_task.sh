#!/bin/bash
set -e
echo "=== Setting up PII Redaction Task ==="

source /workspace/scripts/task_utils.sh

WAZUH_MANAGER="wazuh-wazuh.manager-1"

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Manager is running
echo "Checking Wazuh Manager status..."
if ! docker ps | grep -q "$WAZUH_MANAGER"; then
    echo "Starting Wazuh Manager..."
    docker start "$WAZUH_MANAGER"
    sleep 20
fi

# 2. Configure ossec.conf to read payments.json as JSON
# We use a python script to inject the XML safely into the container
cat > /tmp/inject_conf.py << 'EOF'
import sys
import os

conf_path = "/var/ossec/etc/ossec.conf"
# Check if file exists inside container context
if not os.path.exists(conf_path):
    print("ossec.conf not found")
    sys.exit(1)

with open(conf_path, "r") as f:
    content = f.read()

new_block = """
  <localfile>
    <log_format>json</log_format>
    <location>/var/ossec/logs/payments.json</location>
  </localfile>
"""

if "payments.json" not in content:
    # Insert before the closing tag
    new_content = content.replace("</ossec_config>", new_block + "\n</ossec_config>")
    with open(conf_path, "w") as f:
        f.write(new_content)
    print("Configuration injected.")
else:
    print("Configuration already present.")
EOF

# Copy script to container and run it
echo "Configuring ossec.conf..."
docker cp /tmp/inject_conf.py "$WAZUH_MANAGER":/tmp/inject_conf.py
docker exec "$WAZUH_MANAGER" python3 /tmp/inject_conf.py
rm /tmp/inject_conf.py

# 3. Create the log file with correct permissions
echo "Creating log file..."
docker exec "$WAZUH_MANAGER" touch /var/ossec/logs/payments.json
docker exec "$WAZUH_MANAGER" chmod 666 /var/ossec/logs/payments.json
docker exec "$WAZUH_MANAGER" chown wazuh:wazuh /var/ossec/logs/payments.json

# 4. Restart Manager to apply ossec.conf changes
echo "Restarting Wazuh Manager..."
docker exec "$WAZUH_MANAGER" /var/ossec/bin/wazuh-control restart
sleep 15

# 5. Start a background simulator (logs every 30s) to create noise/realism
# We run this on the HOST, writing to the container via docker exec
cat > /workspace/background_traffic.sh << 'BGEOF'
#!/bin/bash
WAZUH_MANAGER="wazuh-wazuh.manager-1"
while true; do
    AMT=$((RANDOM % 1000))
    # Generate a fake CC
    CC="4$(printf '%03d' $((RANDOM%1000)))-$(printf '%04d' $((RANDOM%10000)))-$(printf '%04d' $((RANDOM%10000)))-$(printf '%04d' $((RANDOM%10000)))"
    # Create JSON log
    JSON="{\"event\":\"transaction\", \"status\":\"success\", \"amount\":$AMT, \"cc_number\":\"$CC\", \"app_id\":\"payment-gateway\", \"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
    # Append to file inside container
    docker exec "$WAZUH_MANAGER" sh -c "echo '$JSON' >> /var/ossec/logs/payments.json" 2>/dev/null || true
    sleep 30
done
BGEOF

chmod +x /workspace/background_traffic.sh
/workspace/background_traffic.sh > /dev/null 2>&1 &
echo $! > /tmp/bg_pid.txt
echo "Background traffic generator started (PID: $(cat /tmp/bg_pid.txt))"

# 6. Ensure Dashboard is open
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="