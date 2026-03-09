#!/bin/bash
echo "=== Setting up enable_web_statistics task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. ensure acmecorp.test exists (it's pre-seeded, but check)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating required domain acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --unix --dir --web --dns --logrotate
fi

# 2. Disable Webalizer if currently enabled (to ensure clean state)
if virtualmin list-domains --domain acmecorp.test --features | grep -q "Webalizer reporting"; then
    echo "Disabling existing Webalizer feature..."
    virtualmin disable-feature --domain acmecorp.test --webalizer
fi

# 3. Clean up any existing stats directory
rm -rf /home/acmecorp/public_html/stats
echo "Cleaned previous stats."

# 4. Generate realistic access log data
# Webalizer needs data to generate a report. We'll populate the access log.
LOG_FILE="/var/log/virtualmin/acmecorp.test_access_log"
echo "Generating synthetic log data in $LOG_FILE..."

# Python script to generate Apache Combined Log Format entries
python3 -c '
import random
import datetime
import time

log_file = "'$LOG_FILE'"
domains = ["acmecorp.test"]
paths = ["/index.html", "/about", "/products", "/contact", "/images/logo.png", "/css/style.css"]
user_agents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0"
]
status_codes = [200, 200, 200, 200, 301, 404]

# Generate entries for the last 3 days
end_time = datetime.datetime.now()
start_time = end_time - datetime.timedelta(days=3)
current_time = start_time

entries = []
while current_time < end_time:
    # Random time increment between 1 minute and 1 hour
    current_time += datetime.timedelta(minutes=random.randint(1, 60))
    if current_time > end_time:
        break
    
    ip = f"{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}"
    # Format: 10/Oct/2000:13:55:36 -0700
    time_str = current_time.strftime("%d/%b/%Y:%H:%M:%S +0000")
    req = f"GET {random.choice(paths)} HTTP/1.1"
    status = random.choice(status_codes)
    size = random.randint(500, 50000)
    referer = "-"
    ua = random.choice(user_agents)
    
    line = f"{ip} - - [{time_str}] \"{req}\" {status} {size} \"{referer}\" \"{ua}\"\n"
    entries.append(line)

try:
    with open(log_file, "w") as f:
        f.writelines(entries)
    print(f"Successfully wrote {len(entries)} log lines.")
except Exception as e:
    print(f"Error writing logs: {e}")
'

# Ensure permissions are correct for the log file
chmod 644 "$LOG_FILE"

# 5. Open Firefox and log in
ensure_virtualmin_ready

# Navigate to the specific domain to save agent some clicks, but let them find the feature
ACMECORP_ID=$(get_domain_id "acmecorp.test")
navigate_to "https://localhost:10000/virtual-server/edit_domain.cgi?dom=${ACMECORP_ID}"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="