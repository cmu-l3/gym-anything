#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up block_suspicious_ip task ==="

# 1. Setup Ground Truth
# Randomly select a malicious IP
MALICIOUS_IP="203.0.113.$((RANDOM % 250 + 1))"
# Define legitimate IPs
LEGIT_IPS=("192.168.1.45" "10.0.5.22" "172.16.40.11" "198.51.100.55" "192.0.2.8")

# Save ground truth (hidden from agent)
mkdir -p /var/lib/app/ground_truth
echo "$MALICIOUS_IP" > /var/lib/app/ground_truth/attacker_ip.txt
chmod 600 /var/lib/app/ground_truth/attacker_ip.txt

# Save legit IPs for verifier to check false positives
printf "%s\n" "${LEGIT_IPS[@]}" > /var/lib/app/ground_truth/legit_ips.txt
chmod 600 /var/lib/app/ground_truth/legit_ips.txt

# 2. Generate Realistic Access Logs
LOG_FILE="/var/log/virtualmin/acmecorp.test_access_log"
mkdir -p "$(dirname "$LOG_FILE")"

# Create a python script to generate logs
cat <<EOF > /tmp/gen_logs.py
import random
import datetime

malicious_ip = "$MALICIOUS_IP"
# Parse bash array string hack or just split string
legit_ips = "${LEGIT_IPS[*]}".split()

user_agents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0"
]

paths = ["/index.php", "/about.html", "/contact.php", "/assets/style.css", "/assets/logo.png", "/login.php"]

# Start time: 4 hours ago
start_time = datetime.datetime.now() - datetime.timedelta(hours=4)
entries = []

# Generate 200 legitimate entries
for _ in range(200):
    ip = random.choice(legit_ips)
    dt = start_time + datetime.timedelta(seconds=random.randint(1, 14000))
    ts = dt.strftime("%d/%b/%Y:%H:%M:%S +0000")
    
    path = random.choice(paths)
    method = "GET"
    status = 200
    size = random.randint(500, 15000)
    ua = random.choice(user_agents)
    
    # Legit login attempts are rare and usually GET first
    if path == "/login.php" and random.random() > 0.8:
        method = "POST"
    
    entries.append(f'{ip} - - [{ts}] "{method} {path} HTTP/1.1" {status} {size} "-" "{ua}"')

# Generate 50 malicious entries (bursty attack)
attack_time = start_time + datetime.timedelta(hours=3)
for i in range(50):
    ip = malicious_ip
    # Attack happens quickly over 5 minutes
    dt = attack_time + datetime.timedelta(seconds=random.randint(1, 300))
    ts = dt.strftime("%d/%b/%Y:%H:%M:%S +0000")
    
    method = "POST"
    path = "/login.php"
    status = 200 
    size = random.randint(1200, 1300)
    # Attacker sticks to one UA
    ua = "Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/89.0" 
    
    entries.append(f'{ip} - - [{ts}] "{method} {path} HTTP/1.1" {status} {size} "-" "{ua}"')

# Sort by timestamp (string sort works roughly for this format, but let's just dump)
# Ideally sort by date object but for this task simple mix is fine, logs usually appended.
# We'll use a simple sort based on time string inside.
entries.sort(key=lambda x: x.split('[')[1].split(']')[0])

for e in entries:
    print(e)
EOF

# Write logs
python3 /tmp/gen_logs.py > "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 644 "$LOG_FILE"

# 3. Clean Slate & Time Recording
# Clean output file if exists
rm -f /home/ga/blocked_attacker.txt

# Ensure Firewall is in known state (flush custom rules)
if command -v iptables >/dev/null; then
    # Flush input rules but keep policies safe (Virtualmin env might rely on some ports)
    # Ideally we just ensure no specific IP blocks exist yet.
    # We'll trust the base environment config but ensure our target IP isn't already blocked.
    iptables -D INPUT -s "$MALICIOUS_IP" -j DROP 2>/dev/null || true
    iptables -D INPUT -s "$MALICIOUS_IP" -j REJECT 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# 4. GUI Setup
ensure_virtualmin_ready

# Navigate to "Logs and Reports" or System Information initially
# We'll leave it at the dashboard so they have to navigate
navigate_to "https://localhost:10000/virtual-server/index.cgi"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Malicious IP (Internal): $MALICIOUS_IP"