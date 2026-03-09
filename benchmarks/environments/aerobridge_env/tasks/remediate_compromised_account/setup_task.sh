#!/bin/bash
# setup_task.sh - Remedial Security Task

echo "=== Setting up Remediate Compromised Account task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Ensure Server is Ready
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server not ready"

# 2. Setup Users and Logs via Python
# We use Python to interact with Django and generate realistic logs
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
import random
import datetime
from django.utils import timezone

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from django.contrib.auth.models import User

# --- 1. Ensure Users Exist ---
users = ['ops_manager', 'flight_lead', 'logistics_coord']
created_users = []

for username in users:
    user, created = User.objects.get_or_create(username=username)
    if created:
        user.set_password('securepass123')
        user.email = f"{username}@aerobridge.io"
        user.is_staff = True
        user.save()
    # Ensure they start as active
    user.is_active = True
    user.save()
    created_users.append(user)

print(f"Ensured {len(created_users)} operational users exist.")

# --- 2. Select Victim ---
victim = random.choice(users)
print(f"Selected victim: {victim}")

# Write ground truth to a hidden file for export script
with open('/tmp/ground_truth_victim.txt', 'w') as f:
    f.write(victim)

# --- 3. Generate Logs ---
# We'll generate a log file simulating web server/app logs
log_file = '/var/log/aerobridge_server.log'
malicious_ip = '198.51.100.42'
safe_ips = ['192.168.1.105', '192.168.1.106', '10.0.0.52', '10.0.0.88']
user_agents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/89.0"
]

log_entries = []
base_time = datetime.datetime.now() - datetime.timedelta(hours=24)

# Generate background noise (safe traffic)
for _ in range(150):
    timestamp = base_time + datetime.timedelta(minutes=random.randint(1, 1400))
    ip = random.choice(safe_ips)
    user = random.choice(users + ['admin'])
    ua = random.choice(user_agents)
    
    # 90% success, 10% benign failure
    if random.random() > 0.1:
        msg = f"[{timestamp.strftime('%d/%b/%Y %H:%M:%S')}] INFO [django.request] Login successful for user '{user}' from {ip} - {ua}"
    else:
        msg = f"[{timestamp.strftime('%d/%b/%Y %H:%M:%S')}] WARNING [django.request] Login failed for user '{user}' from {ip} - Invalid password"
    
    log_entries.append((timestamp, msg))

# Generate malicious traffic (brute force attempts)
attack_start = base_time + datetime.timedelta(hours=18)
for i in range(20):
    timestamp = attack_start + datetime.timedelta(seconds=i*15)
    target = random.choice(users)
    msg = f"[{timestamp.strftime('%d/%b/%Y %H:%M:%S')}] WARNING [django.request] Login failed for user '{target}' from {malicious_ip} - Invalid password"
    log_entries.append((timestamp, msg))

# Generate THE COMPROMISE (Successful login for victim from malicious IP)
compromise_time = attack_start + datetime.timedelta(minutes=5)
compromise_msg = f"[{compromise_time.strftime('%d/%b/%Y %H:%M:%S')}] INFO [django.request] Login successful for user '{victim}' from {malicious_ip} - Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/89.0"
log_entries.append((compromise_time, compromise_msg))

# Add some post-compromise noise
for i in range(5):
    timestamp = compromise_time + datetime.timedelta(minutes=i*2 + 1)
    msg = f"[{timestamp.strftime('%d/%b/%Y %H:%M:%S')}] INFO [django.server] GET /admin/registry/aircraft/ {random.choice([200, 302])} - from {malicious_ip}"
    log_entries.append((timestamp, msg))

# Sort logs by time and write
log_entries.sort(key=lambda x: x[0])

try:
    with open(log_file, 'w') as f:
        for _, line in log_entries:
            f.write(line + '\n')
    # Set permissions so 'ga' user can read it
    os.chmod(log_file, 0o644)
    print(f"Generated {len(log_entries)} log lines to {log_file}")
except Exception as e:
    print(f"Error writing logs: {e}")

PYEOF

# 3. Launch Firefox to Admin Login
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/"

# 4. Record Start Time
date +%s > /tmp/task_start_time.txt

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="