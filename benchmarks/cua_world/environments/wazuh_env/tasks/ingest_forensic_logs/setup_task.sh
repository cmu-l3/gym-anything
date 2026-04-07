#!/bin/bash
set -e
echo "=== Setting up Ingest Forensic Logs task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for alert verification)
date +%s > /tmp/task_start_time.txt
# Also store ISO format for Elasticsearch queries if needed
date -u +"%Y-%m-%dT%H:%M:%S.000Z" > /tmp/task_start_iso.txt

# Create evidence directory
mkdir -p /home/ga/evidence
chmod 755 /home/ga/evidence

# Generate realistic Apache log with SQL injection attacks
EVIDENCE_FILE="/home/ga/evidence/old_apache.log"
ATTACKER_IP="192.168.50.44"
NORMAL_IP="10.0.0.5"

cat > "$EVIDENCE_FILE" << EOF
$NORMAL_IP - - [24/Oct/2023:10:50:00 -0400] "GET /index.html HTTP/1.1" 200 1024 "-" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
$NORMAL_IP - - [24/Oct/2023:10:51:00 -0400] "GET /about.php HTTP/1.1" 200 512 "-" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
$ATTACKER_IP - - [24/Oct/2023:10:55:00 -0400] "GET /products.php?id=1 HTTP/1.1" 200 2048 "-" "Mozilla/5.0 (Linux; Android 10)"
$ATTACKER_IP - - [24/Oct/2023:10:55:05 -0400] "GET /products.php?id=1' HTTP/1.1" 500 100 "-" "Mozilla/5.0 (Linux; Android 10)"
$ATTACKER_IP - - [24/Oct/2023:10:55:10 -0400] "GET /products.php?id=1' OR '1'='1 HTTP/1.1" 200 50000 "-" "Mozilla/5.0 (Linux; Android 10)"
$ATTACKER_IP - - [24/Oct/2023:10:55:15 -0400] "GET /products.php?id=1 UNION SELECT 1,username,password FROM users-- HTTP/1.1" 200 120 "-" "Mozilla/5.0 (Linux; Android 10)"
$NORMAL_IP - - [24/Oct/2023:11:00:00 -0400] "GET /contact.php HTTP/1.1" 200 800 "-" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
$ATTACKER_IP - - [24/Oct/2023:11:05:00 -0400] "GET /admin/login.php HTTP/1.1" 403 400 "-" "Mozilla/5.0 (Linux; Android 10)"
EOF

chmod 644 "$EVIDENCE_FILE"
chown ga:ga "$EVIDENCE_FILE"

echo "Generated evidence file at $EVIDENCE_FILE with $(wc -l < $EVIDENCE_FILE) lines"

# Ensure clean state: Remove forensic file if it exists in container
docker exec "${WAZUH_MANAGER_CONTAINER}" rm -f /var/ossec/logs/forensic_import.log 2>/dev/null || true

# Ensure clean state: Remove configuration if it exists
docker exec "${WAZUH_MANAGER_CONTAINER}" sed -i '/forensic_import.log/,+3d' /var/ossec/etc/ossec.conf 2>/dev/null || true
# Restart manager to ensure clean config is loaded (optional, but good for stability)
# restart_wazuh_manager

# Ensure Firefox is open to the Wazuh dashboard for the agent
echo "Ensuring Firefox is open..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="