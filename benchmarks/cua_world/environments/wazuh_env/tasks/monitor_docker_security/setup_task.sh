#!/bin/bash
echo "=== Setting up monitor_docker_security task ==="

source /workspace/scripts/task_utils.sh

# 1. timestamp
date +%s > /tmp/task_start_time.txt

# 2. Pre-pull hello-world image so the agent can easily tag it
echo "Pre-pulling hello-world image..."
docker pull hello-world:latest > /dev/null 2>&1 || true

# 3. Clean up any previous runs (Reset ossec.conf and local_rules.xml)
echo "Resetting Wazuh configuration..."
CONTAINER="wazuh-wazuh.manager-1"

# Disable docker-listener if enabled (remove the block or ensure disabled)
# We'll just replace the block with a disabled one or remove it if safe.
# For simplicity, we'll try to ensure it's NOT enabled.
# Using sed to find and disable or just accepting default state if it wasn't there.
# To be robust, let's restore a 'clean' config snippet if needed, but editing xml with sed is risky.
# We will check if it exists and 'no' it.
docker exec "$CONTAINER" sed -i '/<wodle name="docker-listener">/,/<\/wodle>/d' /var/ossec/etc/ossec.conf 2>/dev/null || true

# Remove the custom rule 100205 if it exists
# We'll just overwrite local_rules.xml with a clean version to be sure
CLEAN_RULES='<!-- Custom rules for Wazuh -->
<group name="local,syslog,sshd,">
</group>
'
echo "$CLEAN_RULES" > /tmp/clean_rules.xml
docker cp /tmp/clean_rules.xml "$CONTAINER":/var/ossec/etc/rules/local_rules.xml
rm /tmp/clean_rules.xml
docker exec "$CONTAINER" chown root:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec "$CONTAINER" chmod 660 /var/ossec/etc/rules/local_rules.xml

# Restart manager to apply clean state
echo "Restarting Wazuh manager to apply clean state..."
docker exec "$CONTAINER" /var/ossec/bin/wazuh-control restart > /dev/null 2>&1
sleep 5

# 4. Open Firefox to Dashboard (helpful context)
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# 5. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="