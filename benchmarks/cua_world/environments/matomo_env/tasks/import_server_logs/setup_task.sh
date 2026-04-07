#!/bin/bash
# Setup script for Import Server Logs task

echo "=== Setting up Import Server Logs Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Directories
mkdir -p /home/ga/Documents/access_logs
mkdir -p /home/ga/tools
chown -R ga:ga /home/ga/Documents/access_logs
chown -R ga:ga /home/ga/tools

# 2. Extract import_logs.py from the Matomo container
echo "Extracting import_logs.py from container..."
# The script is usually located at misc/log-analytics/import_logs.py
if docker cp matomo-app:/var/www/html/misc/log-analytics/import_logs.py /home/ga/tools/import_logs.py; then
    echo "Import script copied successfully."
else
    echo "ERROR: Could not find import_logs.py in container. Fetching from GitHub as fallback."
    curl -sS https://raw.githubusercontent.com/matomo-org/matomo-log-analytics/master/import_logs.py -o /home/ga/tools/import_logs.py
fi
chmod +x /home/ga/tools/import_logs.py
chown ga:ga /home/ga/tools/import_logs.py

# 3. Generate Auth Token
echo "Generating API Token..."
# Use Matomo console to create a token for 'admin'
# Note: 'admin' user is created by setup_matomo.sh
TOKEN_AUTH=$(docker exec matomo-app php /var/www/html/console users:generate-token --user=admin --confirm | grep -oE '[a-f0-9]{32}' | head -1)

if [ -z "$TOKEN_AUTH" ]; then
    echo "WARNING: Failed to generate token via console. Inserting manually."
    TOKEN_AUTH=$(openssl rand -hex 16)
    TOKEN_HASH=$(docker exec matomo-app php -r "echo password_hash('${TOKEN_AUTH}', PASSWORD_BCRYPT);")
    matomo_query "INSERT INTO matomo_user_token (login, description, token_hash, date_created) VALUES ('admin', 'Log Import Task', '${TOKEN_HASH}', NOW())"
fi

echo "$TOKEN_AUTH" > /home/ga/tools/auth_token.txt
chown ga:ga /home/ga/tools/auth_token.txt
chmod 600 /home/ga/tools/auth_token.txt

# 4. Generate Realistic Apache Access Logs
echo "Generating Apache access logs..."

cat << 'PYEOF' > /tmp/generate_logs.py
import random
import datetime
import time

# Configuration
NUM_VISITS = 250
START_DATE = datetime.datetime.now() - datetime.timedelta(days=7)
OUTPUT_FILE = "/home/ga/Documents/access_logs/apache_access.log"

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
]

URLS = [
    "/",
    "/about",
    "/contact",
    "/products",
    "/services",
    "/blog/post-1",
    "/blog/post-2",
    "/blog/post-3",
    "/shop/category/electronics",
    "/shop/item/laptop",
]

STATUS_CODES = [200, 200, 200, 200, 200, 200, 301, 302, 304, 404, 403, 500]
METHODS = ["GET", "GET", "GET", "POST"]

with open(OUTPUT_FILE, "w") as f:
    current_time = START_DATE
    for i in range(NUM_VISITS):
        # Advance time by random amount (1 min to 2 hours)
        current_time += datetime.timedelta(seconds=random.randint(60, 7200))
        
        ip = f"{random.randint(1, 255)}.{random.randint(1, 255)}.{random.randint(1, 255)}.{random.randint(1, 255)}"
        user_id = "-"
        auth_user = "-"
        
        # Apache Log Date Format: [10/Oct/2000:13:55:36 -0700]
        date_str = current_time.strftime("[%d/%b/%Y:%H:%M:%S +0000]")
        
        method = random.choice(METHODS)
        url = random.choice(URLS)
        proto = "HTTP/1.1"
        request = f"{method} {url} {proto}"
        
        status = random.choice(STATUS_CODES)
        size = random.randint(500, 15000)
        referrer = "-"
        ua = random.choice(USER_AGENTS)
        
        log_line = f'{ip} {user_id} {auth_user} {date_str} "{request}" {status} {size} "{referrer}" "{ua}"\n'
        f.write(log_line)

print(f"Generated {NUM_VISITS} log entries.")
PYEOF

python3 /tmp/generate_logs.py
chown ga:ga /home/ga/Documents/access_logs/apache_access.log

# 5. Record Initial State
echo "Recording initial state..."
# Ensure site 1 exists
SITE_EXISTS=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE idsite=1")
if [ "$SITE_EXISTS" = "0" ]; then
    echo "Creating Site 1..."
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES (1, 'Initial Site', 'http://localhost', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
fi

INITIAL_VISITS=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE idsite=1")
echo "$INITIAL_VISITS" > /tmp/initial_visit_count.txt
echo "Initial visit count: $INITIAL_VISITS"

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 6. Launch Applications
echo "Starting Firefox..."
pkill -f firefox 2>/dev/null || true
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' &"

# Wait for Firefox
wait_for_window "firefox\|mozilla\|Matomo" 30

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="