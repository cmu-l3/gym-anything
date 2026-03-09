#!/bin/bash
set -e
echo "=== Setting up Web Log Forensics Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
DATA_DIR="/home/ga/Documents/data"
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"

# Create directories
mkdir -p "$DATA_DIR" "$DB_DIR" "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents

# Clean previous run artifacts
rm -f "$DATA_DIR/server_access_logs.csv"
rm -f "$DB_DIR/investigation.db"
rm -f "$EXPORT_DIR/breach_evidence.csv"
rm -f /tmp/forensic_ground_truth.json

# Generate realistic server log CSV using Python
echo "Generating log data..."
python3 -c '
import csv
import random
import datetime
import json
import os

output_file = "/home/ga/Documents/data/server_access_logs.csv"
gt_file = "/tmp/forensic_ground_truth.json"

# Configuration
ips = ["10.0." + str(x) + "." + str(y) for x in range(1, 5) for y in range(1, 50)]
attacker_ip = "192.168.100.66"
sensitive_file = "/admin/config.xml"

endpoints_common = ["/index.html", "/about", "/contact", "/products", "/login", "/static/style.css", "/static/logo.png"]
user_agents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0"
]

rows = []
start_time = datetime.datetime.now() - datetime.timedelta(days=1)

# 1. Generate Background Traffic (Normal)
# ~2000 rows of normal traffic
for _ in range(2000):
    ip = random.choice(ips)
    dt = start_time + datetime.timedelta(seconds=random.randint(0, 86400))
    endpoint = random.choice(endpoints_common)
    method = "GET"
    
    # 95% success rate for normal traffic
    status = 200 if random.random() < 0.95 else 404
    
    ua = random.choice(user_agents)
    rows.append([ip, dt.isoformat(), method, endpoint, status, ua])

# 2. Generate Attack Traffic (Brute Force Scan)
# Attacker tries many missing files (high 404 count)
scan_start = start_time + datetime.timedelta(hours=14)
for i in range(150):
    dt = scan_start + datetime.timedelta(seconds=i*2) # Rapid fire
    endpoint = f"/admin/vulnerable_file_{random.randint(1,999)}.php"
    rows.append([attacker_ip, dt.isoformat(), "GET", endpoint, 404, "Python-urllib/3.8"])

# 3. The Successful Breach (The Needle in the Haystack)
breach_time = scan_start + datetime.timedelta(minutes=10)
rows.append([attacker_ip, breach_time.isoformat(), "GET", sensitive_file, 200, "Python-urllib/3.8"])

# Sort by timestamp
rows.sort(key=lambda x: x[1])

# Write to CSV
with open(output_file, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["ip_address", "timestamp", "method", "endpoint", "status_code", "user_agent"])
    writer.writerows(rows)

# Write Ground Truth
gt = {
    "attacker_ip": attacker_ip,
    "breached_file": sensitive_file,
    "total_rows": len(rows)
}
with open(gt_file, "w") as f:
    json.dump(gt, f)

print(f"Generated {len(rows)} log entries at {output_file}")
'

# Set proper permissions
chown ga:ga "$DATA_DIR/server_access_logs.csv"
chmod 644 "$DATA_DIR/server_access_logs.csv"

# Start DBeaver
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Maximize and focus DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="