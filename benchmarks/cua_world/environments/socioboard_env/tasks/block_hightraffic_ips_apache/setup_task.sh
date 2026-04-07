#!/bin/bash
echo "=== Setting up block_hightraffic_ips_apache task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Apache is running
systemctl is-active --quiet apache2 || systemctl start apache2 || true

# Generate realistic Apache access log dynamically
# We randomize the IPs and counts every run to prevent hardcoding
python3 - << 'EOF'
import random
import json

def generate_ip():
    return f"{random.randint(11, 250)}.{random.randint(1, 250)}.{random.randint(1, 250)}.{random.randint(1, 250)}"

# Generate 3 high-traffic IPs (The targets)
top_ips = [generate_ip() for _ in range(3)]
counts = [random.randint(800, 950), random.randint(600, 750), random.randint(400, 550)]

# Generate 40 normal noise IPs
normal_ips = [generate_ip() for _ in range(40)]

log_ips = []
# Append the targets
for ip, count in zip(top_ips, counts):
    log_ips.extend([ip] * count)
# Append the noise
for ip in normal_ips:
    log_ips.extend([ip] * random.randint(5, 45))

random.shuffle(log_ips)

log_lines = []
for ip in log_ips:
    # Randomize some realistic request fields
    method = random.choice(["GET", "POST", "GET"])
    url = random.choice(["/", "/login", "/api/data", "/images/logo.png", "/about"])
    status = random.choice([200, 200, 200, 404, 500])
    size = random.randint(500, 5000)
    log_lines.append(f'{ip} - - [10/Oct/2023:13:55:36 -0700] "{method} {url} HTTP/1.1" {status} {size} "-" "Mozilla/5.0"')

with open("/home/ga/historical_access.log", "w") as f:
    f.write("\n".join(log_lines) + "\n")

# Save ground truth for the verifier
truth = [{"ip": ip, "count": count} for ip, count in zip(top_ips, counts)]
truth.sort(key=lambda x: x["count"], reverse=True)

with open("/tmp/ground_truth.json", "w") as f:
    json.dump(truth, f)
EOF

# Set proper permissions
chown ga:ga /home/ga/historical_access.log
chmod 644 /home/ga/historical_access.log

# Ensure blocked_ips.txt doesn't exist from a previous run
rm -f /home/ga/blocked_ips.txt

# Open a terminal so the agent is ready to start analyzing
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 3
fi

# Maximize the terminal for better visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="