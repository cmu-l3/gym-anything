#!/bin/bash
set -e
echo "=== Setting up offline incident analysis task ==="

# 1. Create directory structure
mkdir -p /home/ga/evidence
GROUND_TRUTH="/var/lib/wazuh-task-truth.json"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Generate the realistic log dump using Python
# We embed the python script to ensure it runs within the container environment
cat << 'EOF' > /tmp/generate_logs.py
import json
import random
import sys
from datetime import datetime, timedelta, timezone

# --- Config Randomization ---
# Internal IPs
ips = [f"192.168.1.{i}" for i in range(10, 50)]
# External IPs (Attacker candidates)
external_ips = [f"{random.randint(1,220)}.{random.randint(1,250)}.{random.randint(1,250)}.{random.randint(1,250)}" for _ in range(20)]
# Users
users = ["admin", "root", "deploy", "backup", "operator", "postgres", "webmaster"]

attacker_ip = random.choice([ip for ip in external_ips if not ip.startswith("192.168")])
target_user = random.choice(users)
# Start time roughly 2 days ago
base_time = datetime.now(timezone.utc) - timedelta(days=2)

print(f"DEBUG: Attacker={attacker_ip}, User={target_user}")

logs = []

# --- Helper to create Wazuh alert structure ---
def create_alert(ts, rule_id, level, desc, srcip, dstuser, groups):
    # Format: 2023-10-27T10:00:00.123+0000
    ts_str = ts.strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + "+0000"
    
    return {
        "timestamp": ts_str,
        "rule": {
            "level": level,
            "description": desc,
            "id": str(rule_id),
            "groups": groups,
            "firedtimes": random.randint(1, 10),
            "mail": False,
            "pci_dss": ["10.2.4", "10.2.5"]
        },
        "agent": {
            "id": "001",
            "name": "web-server-prod",
            "ip": "192.168.1.5"
        },
        "manager": {
            "name": "wazuh-manager"
        },
        "id": f"163{random.randint(100000,999999)}.{random.randint(100000,999999)}",
        "decoder": {
            "name": "sshd"
        },
        "data": {
            "srcip": srcip,
            "dstuser": dstuser,
            "srcport": str(random.randint(1024, 65535))
        },
        "location": "/var/log/auth.log"
    }

current_time = base_time

# --- 1. Pre-Attack Noise (Normal Traffic) ---
for _ in range(random.randint(400, 800)):
    current_time += timedelta(seconds=random.randint(1, 300))
    
    # Random successful internal logins
    if random.random() < 0.2:
        u = random.choice(users)
        src = random.choice(ips)
        logs.append(create_alert(
            current_time, "5715", 3, "SSHD: authentication success.", 
            src, u, ["syslog", "sshd", "authentication_success"]
        ))
    # Occasional failed login (typo)
    elif random.random() < 0.05:
        u = random.choice(users)
        src = random.choice(ips)
        logs.append(create_alert(
            current_time, "5716", 5, "SSHD: authentication failed.", 
            src, u, ["syslog", "sshd", "authentication_failed"]
        ))

# --- 2. The Attack Sequence ---

# Phase A: Brute Force Start
# Attacker starts hammering a specific user or random users
attack_start_ts = None
attack_start_obj = None

attempts = random.randint(50, 150)
for i in range(attempts):
    # Fast attempts (100ms - 1.5s apart)
    current_time += timedelta(milliseconds=random.randint(100, 1500))
    
    if i == 0:
        attack_start_obj = current_time
        # Re-format to string to ensure we match exactly what is written to JSON
        attack_start_ts = attack_start_obj.strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + "+0000"

    # Mix of invalid user and valid user failures
    if random.random() < 0.7:
        logs.append(create_alert(
            current_time, "5710", 5, "SSHD: Attempt to login using a non-existent user", 
            attacker_ip, "invalid_user", ["syslog", "sshd", "authentication_failed", "invalid_login"]
        ))
    else:
        logs.append(create_alert(
            current_time, "5716", 5, "SSHD: authentication failed.", 
            attacker_ip, target_user, ["syslog", "sshd", "authentication_failed"]
        ))

# Phase B: Compromise (Successful Login)
# 2-10 seconds after last failure
current_time += timedelta(seconds=random.randint(2, 10))
compromise_obj = current_time
compromise_ts = compromise_obj.strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + "+0000"

logs.append(create_alert(
    current_time, "5715", 3, "SSHD: authentication success.", 
    attacker_ip, target_user, ["syslog", "sshd", "authentication_success"]
))

# Phase C: Persistence (User Creation)
# 1-5 minutes after login
current_time += timedelta(minutes=random.randint(1, 5))
logs.append(create_alert(
    current_time, "5902", 8, "New user account added", 
    attacker_ip, "service_backup_d", ["syslog", "adduser", "account_creation"]
))

# --- 3. Post-Attack Noise ---
for _ in range(random.randint(200, 400)):
    current_time += timedelta(seconds=random.randint(1, 300))
    logs.append(create_alert(
        current_time, "5715", 3, "SSHD: authentication success.", 
        random.choice(ips), random.choice(users), ["syslog", "sshd", "authentication_success"]
    ))

# Write Logs
with open('/home/ga/evidence/recovered_alerts.json', 'w') as f:
    for log in logs:
        f.write(json.dumps(log) + '\n')

# Write Ground Truth (hidden)
truth = {
    "attacker_ip": attacker_ip,
    "compromised_user": target_user,
    "attack_start_timestamp": attack_start_ts,
    "compromise_timestamp": compromise_ts,
    "time_to_compromise_seconds": int((compromise_obj - attack_start_obj).total_seconds())
}
with open('/var/lib/wazuh-task-truth.json', 'w') as f:
    json.dump(truth, f)

print("Logs generated successfully.")
EOF

# Run generator
python3 /tmp/generate_logs.py
rm /tmp/generate_logs.py

# Set permissions
chown ga:ga /home/ga/evidence/recovered_alerts.json
chmod 644 /home/ga/evidence/recovered_alerts.json

# 3. Environment State Setup
# Open a terminal focused on the evidence directory so the agent is ready to work
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/evidence &"
    sleep 2
fi

# Maximize terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="