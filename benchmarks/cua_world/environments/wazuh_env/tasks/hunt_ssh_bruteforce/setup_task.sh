#!/bin/bash
echo "=== Setting up hunt_ssh_bruteforce task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
rm -f /home/ga/threat_hunt_report.json 2>/dev/null

# Ensure Wazuh Indexer (OpenSearch) is running
echo "Waiting for Wazuh Indexer..."
wait_for_service "Wazuh Indexer" "curl -sk -u admin:SecretPassword https://localhost:9200/_cluster/health" 120

# Create Python script to generate synthetic alert data
cat > /tmp/generate_data.py << 'PYEOF'
import json
import random
import time
from datetime import datetime, timedelta

# Configuration
INDEX_NAME = "wazuh-alerts-4.x-2024.01.15"
TOTAL_RECORDS = 200

# Attack Scenarios
ATTACKERS = [
    # IP, Fail Count, Success Targets, Agent ID
    ("185.220.101.42", 87, [("web-server-01", "001")]),
    ("45.33.32.156", 43, []),
    ("103.253.41.98", 15, [("db-server-01", "002")])
]

AGENTS = [
    {"id": "001", "name": "web-server-01", "ip": "192.168.1.10"},
    {"id": "002", "name": "db-server-01", "ip": "192.168.1.20"},
    {"id": "003", "name": "mail-server-01", "ip": "192.168.1.30"},
    {"id": "000", "name": "wazuh-manager", "ip": "127.0.0.1"}
]

USERS = ["root", "admin", "user", "test", "oracle", "postgres", "deploy"]

# Helper to create alert document
def create_alert(timestamp, rule_id, level, description, agent, srcip, dstuser, outcome):
    return {
        "timestamp": timestamp,
        "rule": {
            "level": level,
            "description": description,
            "id": str(rule_id),
            "firedtimes": 1,
            "mail": False,
            "groups": ["syslog", "sshd", "authentication_failed" if outcome == "failure" else "authentication_success"]
        },
        "agent": {"id": agent["id"], "name": agent["name"], "ip": agent["ip"]},
        "manager": {"name": "wazuh-manager"},
        "id": f"100{random.randint(1000,9999)}",
        "decoder": {"name": "sshd"},
        "data": {
            "srcip": srcip,
            "dstuser": dstuser,
            "srcport": str(random.randint(10000, 60000))
        },
        "location": "/var/log/auth.log"
    }

records = []
base_time = datetime(2024, 1, 15, 12, 0, 0)

# 1. Inject Attack Data
for ip, fail_count, success_targets in ATTACKERS:
    # Failures
    for _ in range(fail_count):
        t = base_time + timedelta(minutes=random.randint(0, 1400))
        agent = random.choice(AGENTS)
        user = random.choice(USERS)
        records.append(create_alert(t.isoformat(), 5716, 5, "SSHD authentication failed.", agent, ip, user, "failure"))
    
    # Successes (Compromise)
    for target_name, target_id in success_targets:
        # Find agent object
        agent = next(a for a in AGENTS if a["id"] == target_id)
        # Success happens AFTER some failures
        t = base_time + timedelta(minutes=1420) 
        records.append(create_alert(t.isoformat(), 5715, 3, "SSHD authentication success.", agent, ip, "root", "success"))

# 2. Inject Noise / Normal Traffic
# Normal failures (users mistyping)
for _ in range(20):
    t = base_time + timedelta(minutes=random.randint(0, 1440))
    agent = random.choice(AGENTS)
    ip = f"192.168.1.{random.randint(100, 200)}"
    records.append(create_alert(t.isoformat(), 5716, 5, "SSHD authentication failed.", agent, ip, "admin", "failure"))

# Normal successes
for _ in range(20):
    t = base_time + timedelta(minutes=random.randint(0, 1440))
    agent = random.choice(AGENTS)
    ip = f"192.168.1.{random.randint(100, 200)}"
    records.append(create_alert(t.isoformat(), 5715, 3, "SSHD authentication success.", agent, ip, "admin", "success"))

# Other noise (FIM, etc)
for _ in range(30):
    t = base_time + timedelta(minutes=random.randint(0, 1440))
    agent = random.choice(AGENTS)
    records.append({
        "timestamp": t.isoformat(),
        "rule": {"level": 3, "description": "File integrity monitoring event", "id": "550", "groups": ["ossec", "syscheck"]},
        "agent": {"id": agent["id"], "name": agent["name"]},
        "syscheck": {"path": "/etc/hosts", "event": "modified"}
    })

# Output Bulk NDJSON
with open("/tmp/bulk_data.json", "w") as f:
    for r in records:
        f.write(json.dumps({"index": {"_index": INDEX_NAME}}) + "\n")
        f.write(json.dumps(r) + "\n")

print(f"Generated {len(records)} records")
PYEOF

# Generate the data
echo "Generating synthetic alert data..."
python3 /tmp/generate_data.py

# Inject data into OpenSearch
echo "Injecting data into Wazuh Indexer..."
curl -sk -u admin:SecretPassword -X POST "https://localhost:9200/_bulk" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/bulk_data.json > /dev/null

# Refresh index to make data searchable immediately
curl -sk -u admin:SecretPassword -X POST "https://localhost:9200/wazuh-alerts-*/_refresh" > /dev/null

echo "Data injection complete."

# Prepare Firefox (User might want to use Dashboard)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 2

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="