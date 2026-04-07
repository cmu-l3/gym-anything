#!/bin/bash
# setup_task.sh for visualize_web_attacks_dashboard
set -e

echo "=== Setting up Web Attack Analysis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Generate and Inject Simulated Web Attack Data
# ==============================================================================
echo "Generating simulated web attack data..."

# Python script to generate bulk ndjson for OpenSearch
cat > /tmp/generate_data.py << 'PYEOF'
import json
import random
import datetime
import uuid

# Configuration
NUM_RECORDS = 500
TODAY = datetime.datetime.now(datetime.timezone.utc)
INDEX_NAME = f"wazuh-alerts-4.x-{TODAY.strftime('%Y.%m.%d')}"

# Attack Scenarios
ATTACKS = [
    {"desc": "SQL Injection attempt", "id": "31103", "level": 12, "method": "GET", "url_pattern": "/products?id=1' OR '1'='1"},
    {"desc": "XSS (Cross Site Scripting) attempt", "id": "31106", "level": 10, "method": "POST", "url_pattern": "/comment?msg=<script>alert(1)</script>"},
    {"desc": "Directory Traversal", "id": "31101", "level": 10, "method": "GET", "url_pattern": "/../../etc/passwd"},
    {"desc": "Web server 400 error code", "id": "31100", "level": 5, "method": "GET", "url_pattern": "/random_junk"},
    {"desc": "Shellshock attack attempt", "id": "31151", "level": 15, "method": "GET", "url_pattern": "/cgi-bin/test.sh"},
]

IPS = ["192.168.1.50", "10.0.0.15", "172.16.23.44", "45.33.22.11", "185.22.1.9", "192.168.1.50"] # Repeated IP for "Top Attacker"

data = []
for i in range(NUM_RECORDS):
    # Time distribution over last 24 hours
    minutes_ago = random.randint(0, 1440)
    timestamp = (TODAY - datetime.timedelta(minutes=minutes_ago)).isoformat()
    
    attack = random.choice(ATTACKS)
    srcip = random.choice(IPS)
    
    # 80% chance it's a web attack, 20% random other noise
    if random.random() < 0.8:
        groups = ["web", "access_log"]
        rule = {
            "id": attack["id"],
            "level": attack["level"],
            "description": attack["desc"],
            "groups": groups
        }
        event_data = {
            "srcip": srcip,
            "method": attack["method"],
            "url": attack["url_pattern"],
            "id": str(uuid.uuid4())
        }
    else:
        # Noise
        groups = ["syslog"]
        rule = {
            "id": "1002",
            "level": 2,
            "description": "Unknown problem",
            "groups": groups
        }
        event_data = {
            "srcip": "127.0.0.1",
            "msg": "background noise"
        }

    # OpenSearch Bulk Action
    action = {"index": {"_index": INDEX_NAME}}
    doc = {
        "@timestamp": timestamp,
        "rule": rule,
        "data": event_data,
        "agent": {"id": "000", "name": "wazuh-manager"},
        "manager": {"name": "wazuh-manager"}
    }
    
    data.append(json.dumps(action))
    data.append(json.dumps(doc))

with open("/tmp/web_attacks_bulk.json", "w") as f:
    f.write("\n".join(data) + "\n")

print(f"Generated {NUM_RECORDS} records for index {INDEX_NAME}")
PYEOF

python3 /tmp/generate_data.py

# Inject data into Indexer
echo "Injecting data into Wazuh Indexer..."
# Wait for indexer to be ready
wait_for_service "Wazuh Indexer" "curl -sk -u admin:SecretPassword https://localhost:9200/"

# Post bulk data
curl -sk -u admin:SecretPassword \
    -H "Content-Type: application/x-ndjson" \
    -XPOST "https://localhost:9200/_bulk" \
    --data-binary "@/tmp/web_attacks_bulk.json" > /tmp/injection_result.json

echo "Data injection complete."

# ==============================================================================
# 2. Environment Setup
# ==============================================================================

# Ensure Firefox is open to the Dashboard
echo "Ensuring Firefox is open..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Wait for Dashboard to be ready and loaded
sleep 10

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="