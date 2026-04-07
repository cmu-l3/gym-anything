#!/bin/bash
# Setup for add_application_log_source task

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || { echo "Failed to source task_utils"; exit 1; }

echo "=== Setting up add_application_log_source task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for EventLog Analyzer to be ready
wait_for_eventlog_analyzer 900
if [ $? -ne 0 ]; then
    echo "ERROR: EventLog Analyzer not ready"
    exit 1
fi

# =====================================================
# Prepare Real Data: Apache Access Log
# =====================================================
echo "Preparing Apache access log file..."
mkdir -p /home/ga/log_samples

# Generate realistic Apache Combined Log Format entries
python3 << 'PYEOF'
import random
import datetime

output_path = "/home/ga/log_samples/apache_access.log"

source_ips = [
    "192.168.1.10", "192.168.1.15", "10.0.0.5", "10.0.0.100", 
    "172.16.0.3", "172.16.0.45", "192.168.10.20"
]

user_agents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0",
    "python-requests/2.31.0",
    "curl/8.4.0"
]

paths = [
    "/index.html", "/about.html", "/contact.html", "/products", "/api/v1/status", 
    "/css/style.css", "/js/app.js", "/images/logo.png", "/login", "/dashboard"
]

methods = ["GET", "GET", "GET", "POST", "HEAD"]
status_codes = [200, 200, 200, 301, 302, 404, 500]

now = datetime.datetime.now()
lines = []

# Generate 300 entries over the last 24 hours
for i in range(300):
    offset = random.randint(0, 86400)
    entry_time = now - datetime.timedelta(seconds=offset)
    timestamp = entry_time.strftime("%d/%b/%Y:%H:%M:%S +0000")
    
    ip = random.choice(source_ips)
    method = random.choice(methods)
    path = random.choice(paths)
    status = random.choice(status_codes)
    size = random.randint(200, 50000)
    ua = random.choice(user_agents)
    
    line = f'{ip} - - [{timestamp}] "{method} {path} HTTP/1.1" {status} {size} "-" "{ua}"'
    lines.append((entry_time, line))

lines.sort(key=lambda x: x[0])

with open(output_path, "w") as f:
    for _, line in lines:
        f.write(line + "\n")
PYEOF

chown ga:ga /home/ga/log_samples/apache_access.log
chmod 644 /home/ga/log_samples/apache_access.log
echo "Apache log generated at /home/ga/log_samples/apache_access.log"

# =====================================================
# Record Initial State
# =====================================================
# We count existing devices to detect if a new one is added
INITIAL_COUNT=$(ela_db_query "SELECT COUNT(*) FROM devicetable" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_device_count.txt
echo "Initial device count: $INITIAL_COUNT"

# =====================================================
# Launch Application
# =====================================================
# Launch Firefox pointing to the Settings/AppsHome page
# Using AppsHome.do ensures the main app loads, then we click Settings
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 5

# Navigate to Settings via UI interaction to ensure correct context
# Click 'Settings' tab (coordinates approx for 1920x1080)
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
    sleep 1
    # Click Settings tab
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 618 203 click 1
    echo "Clicked Settings tab"
    sleep 2
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="