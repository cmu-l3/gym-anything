#!/bin/bash
set -e
echo "=== Setting up Detect DNS Tunneling task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Prepare Sample Data content
SAMPLE_CONTENT='2023-10-27T14:02:11 dns-edge-01 query_log: client_ip="192.168.1.50" domain="google.com" type="A"
2023-10-27T14:02:12 dns-edge-01 query_log: client_ip="192.168.1.51" domain="yahoo.com" type="A"
2023-10-27T14:02:15 dns-edge-01 query_log: client_ip="192.168.1.52" domain="very-long-encoded-string-that-looks-like-base64-exfiltration-data.attacker-site.com" type="TXT"
2023-10-27T14:02:18 dns-edge-01 query_log: client_ip="192.168.1.53" domain="azure.microsoft.com" type="CNAME"'

# 2. Place sample data for the agent to analyze in /home/ga
echo "$SAMPLE_CONTENT" > /home/ga/dns_sample_data.log
chmod 644 /home/ga/dns_sample_data.log
chown ga:ga /home/ga/dns_sample_data.log

# 3. Place the "active" log file inside the container (this is what they need to ingest)
# We put some initial benign data in it
BENIGN_CONTENT='2023-10-27T14:00:00 dns-edge-01 query_log: client_ip="10.0.0.1" domain="startup-check.local" type="A"'
TEMP_LOG=$(mktemp)
echo "$BENIGN_CONTENT" > "$TEMP_LOG"
docker cp "$TEMP_LOG" "${CONTAINER}:/var/log/custom_dns.log"
docker exec "${CONTAINER}" chmod 644 /var/log/custom_dns.log
rm -f "$TEMP_LOG"

# 4. Clean up local_decoder.xml and local_rules.xml to ensure fresh start
# (Keep the root tags)
CLEAN_DECODER='<decoder name="local_decoder_example">
    <program_name>example_program</program_name>
</decoder>'

CLEAN_RULES='<group name="local,syslog,">
</group>'

TEMP_FILE=$(mktemp)
echo "$CLEAN_DECODER" > "$TEMP_FILE"
docker cp "$TEMP_FILE" "${CONTAINER}:/var/ossec/etc/decoders/local_decoder.xml"

echo "$CLEAN_RULES" > "$TEMP_FILE"
docker cp "$TEMP_FILE" "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml"
rm -f "$TEMP_FILE"

# 5. Restart Wazuh manager to apply clean state
echo "Restarting Wazuh manager to apply clean state..."
docker restart "${CONTAINER}"
sleep 5

# 6. Ensure Firefox is ready (optional for this task, but good for environment consistency)
echo "Ensuring Firefox is ready..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="