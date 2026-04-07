#!/bin/bash
set -e

echo "=== Setting up Emoncms ==="

XAUTH="/run/user/1000/gdm/Xauthority"
EMONCMS_DIR="/home/ga/emoncms"
EMONCMS_URL="http://localhost"

# -----------------------------------------------------------------------
# 1. Wait for Docker daemon
# -----------------------------------------------------------------------
wait_for_docker() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker daemon is ready"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: Docker daemon not ready after ${timeout}s"
    return 1
}
wait_for_docker

# -----------------------------------------------------------------------
# 2. Authenticate with Docker Hub to avoid rate limits
# -----------------------------------------------------------------------
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin \
        && echo "Docker Hub auth successful" \
        || echo "Docker Hub auth failed (continuing anyway)"
else
    echo "No .dockerhub_credentials found – proceeding without authentication"
fi

# -----------------------------------------------------------------------
# 3. Copy docker-compose to writable directory and start
# -----------------------------------------------------------------------
mkdir -p "$EMONCMS_DIR"
cp /workspace/config/docker-compose.yml "$EMONCMS_DIR/"
chown -R ga:ga "$EMONCMS_DIR"

echo "=== Pulling Emoncms Docker images (this may take several minutes) ==="
cd "$EMONCMS_DIR"
docker compose pull

echo "=== Starting Emoncms services ==="
docker compose up -d

# -----------------------------------------------------------------------
# 4. Wait for Emoncms web service to be ready
# -----------------------------------------------------------------------
wait_for_emoncms() {
    local timeout=300
    local elapsed=0
    echo "Waiting for Emoncms web service..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${EMONCMS_URL}/" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "Emoncms is responding (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Still waiting... ${elapsed}s (last HTTP: $HTTP_CODE)"
    done
    echo "ERROR: Emoncms did not become ready within ${timeout}s"
    docker compose logs web | tail -50
    return 1
}
wait_for_emoncms

# Give the app more time to fully initialize DB schema
sleep 15

# -----------------------------------------------------------------------
# 5. CRITICAL: Write settings.ini with hardcoded values inside the container
#
#    Emoncms uses settings.ini with {{PLACEHOLDER}} env vars resolved by
#    resolve_env_vars() via getenv(). This works when supervisord starts
#    Apache (env vars inherited), but BREAKS after Apache restart because
#    the new Apache process doesn't inherit Docker env vars.
#
#    Fix: write settings.ini with actual values so emoncms never needs
#    getenv() at all. This is idempotent and survives any Apache restart.
# -----------------------------------------------------------------------
echo "=== Writing hardcoded settings.ini inside container ==="
docker exec emoncms-web bash -c "
cat > /var/www/emoncms/settings.ini << 'SETTINGS_EOF'
[sql]
server = db
database = emoncms
username = emoncms
password = emoncms
port = 3306

[redis]
enabled = true
host = redis
port = 6379
prefix = emoncms

[mqtt]
enabled = false
host = localhost
client_id = emoncmsmqtt
user = emonpi
password = emonpimqtt2016
basetopic = emon
port = 1883

[feed]
phpfina[datadir] = /var/opt/emoncms/phpfina/
phptimeseries[datadir] = /var/opt/emoncms/phptimeseries/
SETTINGS_EOF
echo 'settings.ini written successfully'
"

# -----------------------------------------------------------------------
# 6. Create admin user directly via MySQL (more reliable than web form)
#
#    Emoncms password hash: sha256(salt + sha256(password))
#    Salt is stored in users.salt column.
#    API keys must be exactly 32 hex characters.
# -----------------------------------------------------------------------
echo "=== Creating admin user via MySQL ==="

# Check if admin user already exists
ADMIN_EXISTS=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N \
    -e "SELECT COUNT(*) FROM users WHERE username='admin'" 2>/dev/null | head -1 || echo "0")

if [ "${ADMIN_EXISTS}" = "0" ] || [ -z "${ADMIN_EXISTS}" ]; then
    # Create admin user with Python on the host (NOT inside emoncms-web), using
    # 'docker exec emoncms-db mysql' so MySQL connection goes to the correct container.
    python3 << 'PYTHON_ADMIN_EOF'
import hashlib
import secrets
import subprocess

# Admin credentials
username = 'admin'
email = 'admin@emoncms.local'
password = 'admin'

# Generate salt and API keys (MUST be exactly 32 hex chars for API keys)
salt = secrets.token_hex(8)  # 16 char salt  (matches emoncms register: 8 bytes)
apikey_write = secrets.token_hex(16)  # 32 char API key
apikey_read  = secrets.token_hex(16)  # 32 char API key

# Emoncms password hash: sha256(salt + sha256(password))
inner = hashlib.sha256(password.encode()).hexdigest()
hashed = hashlib.sha256((salt + inner).encode()).hexdigest()

sql = f"""INSERT INTO users (username, password, email, salt, apikey_write, apikey_read, admin, timezone, language, lastlogin)
VALUES ('{username}', '{hashed}', '{email}', '{salt}', '{apikey_write}', '{apikey_read}', 1, 'UTC', 'en_EN', NOW())
ON DUPLICATE KEY UPDATE
  password='{hashed}', salt='{salt}', apikey_write='{apikey_write}', apikey_read='{apikey_read}', admin=1;
"""

result = subprocess.run(
    ['docker', 'exec', 'emoncms-db', 'mysql', '-u', 'emoncms', '-pemoncms', 'emoncms', '-e', sql],
    capture_output=True, text=True
)
if result.returncode == 0:
    print(f'Admin user created: username={username}, apikey_write={apikey_write}')
else:
    print(f'MySQL error: {result.stderr}')
PYTHON_ADMIN_EOF
    echo "Admin user created"
else
    echo "Admin user already exists, skipping"
fi

# Get admin API keys from database
ADMIN_APIKEY_WRITE=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N \
    -e "SELECT apikey_write FROM users WHERE username='admin'" 2>/dev/null | head -1 || echo "")
ADMIN_APIKEY_READ=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N \
    -e "SELECT apikey_read FROM users WHERE username='admin'" 2>/dev/null | head -1 || echo "")

echo "Admin write API key: ${ADMIN_APIKEY_WRITE}"
echo "Admin read API key: ${ADMIN_APIKEY_READ}"

# Save API keys for task scripts
cat > /home/ga/emoncms_apikeys.sh << APIKEYS_EOF
export EMONCMS_URL="${EMONCMS_URL}"
export EMONCMS_APIKEY_WRITE="${ADMIN_APIKEY_WRITE}"
export EMONCMS_APIKEY_READ="${ADMIN_APIKEY_READ}"
APIKEYS_EOF
chmod 644 /home/ga/emoncms_apikeys.sh
chown ga:ga /home/ga/emoncms_apikeys.sh

# -----------------------------------------------------------------------
# 7. Create realistic energy monitoring seed data
# -----------------------------------------------------------------------
echo "=== Creating energy monitoring seed data ==="

cat > /tmp/emoncms_seed_data.py << 'PYTHON_EOF'
import urllib.request
import urllib.parse
import json
import math
import time
import random
import sys
import subprocess

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost"
APIKEY = sys.argv[2] if len(sys.argv) > 2 else ""

def api_call(endpoint, params=None, data=None):
    """Make an API call to Emoncms"""
    url = f"{BASE_URL}/{endpoint}"
    if params:
        query = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in params.items())
        url = f"{url}?{query}"
    req = urllib.request.Request(url)
    if data:
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        req.data = urllib.parse.urlencode(data).encode('utf-8')
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        print(f"API error for {endpoint}: {e}")
        return None

def mysql(sql):
    """Run a MySQL command inside the emoncms-db container"""
    r = subprocess.run(
        ['docker', 'exec', 'emoncms-db', 'mysql', '-u', 'emoncms', '-pemoncms', 'emoncms', '-N', '-e', sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

def create_feed(name, tag, unit, engine=5, interval=10):
    result = api_call("feed/create.json", {
        "apikey": APIKEY, "name": name, "tag": tag, "datatype": 1,
        "engine": engine, "options": json.dumps({"interval": interval}), "unit": unit
    })
    if result and isinstance(result, dict) and result.get("success"):
        feed_id = result.get("feedid")
        print(f"Created feed: {name} (ID={feed_id})")
        return feed_id
    print(f"Failed to create feed {name}: {result}")
    return None

def insert_feed_data(feed_id, timestamp, value):
    api_call("feed/insert.json", {
        "apikey": APIKEY, "id": feed_id,
        "time": int(timestamp), "value": round(value, 2)
    })

def generate_power_curve(hour, base=300, peak=2500):
    if 6 <= hour <= 9:
        return base + (peak - base) * math.sin(math.pi * (hour - 6) / 3)
    elif 17 <= hour <= 22:
        return base + (peak * 0.8 - base) * math.sin(math.pi * (hour - 17) / 5)
    elif hour >= 23 or hour <= 5:
        return base + random.uniform(-50, 50)
    else:
        return base + random.uniform(100, 400)

def generate_solar(hour):
    if 7 <= hour <= 20:
        return max(0, 3000 * 0.85 * math.sin(math.pi * (hour - 7) / 13) * (0.7 + 0.3 * random.random()))
    return 0

def generate_temp(hour, base=18.0):
    if 6 <= hour <= 22:
        return base + random.uniform(0, 2.5)
    return base - random.uniform(0, 1.5)

# Create feeds
print("Creating feeds...")
feeds = {}
feeds["power1"]   = create_feed("House Power",       "power",       "W",    engine=5, interval=10)
feeds["power2"]   = create_feed("Appliances",         "power",       "W",    engine=5, interval=10)
feeds["solar"]    = create_feed("Solar PV",           "solar",       "W",    engine=5, interval=10)
feeds["temp"]     = create_feed("House Temperature",  "temperature", "degC", engine=5, interval=60)
feeds["heatpump"] = create_feed("Heat Pump Power",    "heat",        "W",    engine=5, interval=10)
feeds["test"]     = create_feed("Test Feed",          "test",        "W",    engine=5, interval=10)
print(f"Feeds: {feeds}")

# Post initial inputs to create input records
print("Creating input records...")
result = api_call("input/post", {
    "apikey": APIKEY, "node": "home",
    "fulljson": json.dumps({"power1": 1500, "power2": 300, "solar": 2000, "temp": 19.5, "heatpump": 800})
})
print(f"Input post: {result}")
time.sleep(2)

# Set input->feed processlists via MySQL (API endpoint is unreliable for this)
print("Setting input processlists via MySQL...")
inputs_list = api_call("input/list.json", {"apikey": APIKEY}) or []
input_map = {inp["name"]: inp["id"] for inp in inputs_list if isinstance(inp, dict)}
print(f"Input map: {input_map}")

process_mapping = {
    "power1":   feeds["power1"],
    "power2":   feeds["power2"],
    "solar":    feeds["solar"],
    "temp":     feeds["temp"],
    "heatpump": feeds["heatpump"],
}

for input_name, feed_id in process_mapping.items():
    input_id = input_map.get(input_name)
    if input_id and feed_id:
        sql = f"UPDATE input SET processList='1:{feed_id}' WHERE id={input_id};"
        r = mysql(sql)
        print(f"Set processlist for {input_name} (id={input_id}) -> feed {feed_id}")
    else:
        print(f"Skipping {input_name}: input_id={input_id}, feed_id={feed_id}")

# Generate 30 days of historical data by writing PHPFina binary files directly.
# This avoids slow per-point HTTP API calls and fills ALL 10-second slots (no gaps).
# PHPFina .dat format: array of IEEE 754 float32, NaN (0xFFFFFFFF) for missing data.
# PHPFina .meta format (bytes 0-15): 4B reserved | 4B reserved | 4B interval(uint32) | 4B start_time(uint32)
print("Generating 30 days of historical data (direct binary write)...")
import struct
import os

DAYS = 30
INTERVAL = 10  # seconds (must match feed creation interval)
POINTS_PER_DAY = 86400 // INTERVAL  # 8640
TOTAL_POINTS = DAYS * POINTS_PER_DAY

now = int(time.time())
start_time = now - DAYS * 86400  # Unix timestamp of first data point
random.seed(42)

def gen_value(feed_name, seconds_from_start):
    """Generate a value for the given feed at the given time offset from start_time."""
    ts = start_time + seconds_from_start
    day_of_week = (ts // 86400) % 7
    hour_f = (ts % 86400) / 3600.0  # fractional hour (0.0 to 23.999)
    hour = int(hour_f)
    if feed_name == "power1":
        v = generate_power_curve(hour) + random.gauss(0, 15)
    elif feed_name == "power2":
        v = generate_power_curve(hour, base=150, peak=800) + random.gauss(0, 10)
    elif feed_name == "solar":
        v = generate_solar(hour)
    elif feed_name == "temp":
        v = generate_temp(hour)
    elif feed_name == "heatpump":
        if hour < 7 or hour > 20:
            v = random.uniform(600, 1200)
        elif 7 <= hour <= 9 or 17 <= hour <= 20:
            v = random.uniform(400, 800)
        else:
            v = random.uniform(0, 200)
    else:
        v = 0
    return max(0.0, v)

# Write PHPFina binary files directly to a temp location, then copy into container
NAN_BYTES = struct.pack('f', float('nan'))  # 0xFFFFFFFF
for feed_name, feed_id in feeds.items():
    if feed_id is None or feed_name == "test":
        continue
    print(f"  Building PHPFina data for {feed_name} (id={feed_id})", flush=True)
    tmp_dat = f"/tmp/phpfina_{feed_id}.dat"
    tmp_meta = f"/tmp/phpfina_{feed_id}.meta"

    # Write .dat file: TOTAL_POINTS float32 values
    with open(tmp_dat, 'wb') as f:
        for i in range(TOTAL_POINTS):
            v = gen_value(feed_name, i * INTERVAL)
            f.write(struct.pack('f', v))

    # Write .meta file: 4B(0) | 4B(0) | 4B(interval uint32) | 4B(start_time uint32)
    with open(tmp_meta, 'wb') as f:
        f.write(struct.pack('I', 0))         # reserved
        f.write(struct.pack('I', 0))         # reserved
        f.write(struct.pack('I', INTERVAL))  # interval = 10 seconds
        f.write(struct.pack('I', start_time))# start_time

    # Copy files into the emoncms-web container
    r_dat = subprocess.run(
        ['docker', 'cp', tmp_dat, f'emoncms-web:/var/opt/emoncms/phpfina/{feed_id}.dat'],
        capture_output=True
    )
    r_meta = subprocess.run(
        ['docker', 'cp', tmp_meta, f'emoncms-web:/var/opt/emoncms/phpfina/{feed_id}.meta'],
        capture_output=True
    )
    # Fix permissions inside container
    subprocess.run(
        ['docker', 'exec', 'emoncms-web', 'chown', 'www-data:www-data',
         f'/var/opt/emoncms/phpfina/{feed_id}.dat',
         f'/var/opt/emoncms/phpfina/{feed_id}.meta'],
        capture_output=True
    )
    os.unlink(tmp_dat)
    os.unlink(tmp_meta)
    dat_size = TOTAL_POINTS * 4
    print(f"    Written {TOTAL_POINTS} points ({dat_size//1024}KB) for {feed_name}")

print(f"Total data points written: {TOTAL_POINTS * len([f for f in feeds if feeds[f] and f != 'test'])}")

# Create dashboard via MySQL (dashboard/create API returns HTML not JSON)
print("Creating dashboard via MySQL...")
userid = mysql("SELECT id FROM users WHERE username='admin'")
if userid:
    sql = f"""INSERT INTO dashboard (userid, name, alias, description, main, public)
SELECT {userid}, 'Energy Overview', 'energy_overview', 'Home energy monitoring dashboard', 0, 0
WHERE NOT EXISTS (SELECT 1 FROM dashboard WHERE name='Energy Overview' AND userid={userid});"""
    mysql(sql)
    print("Dashboard 'Energy Overview' created")

print("=== Seed data complete ===")
PYTHON_EOF

python3 /tmp/emoncms_seed_data.py "${EMONCMS_URL}" "${ADMIN_APIKEY_WRITE}"
echo "Seed data complete"

# -----------------------------------------------------------------------
# 8. Set up Firefox snap profile (suppress first-run dialogs)
# -----------------------------------------------------------------------
FIREFOX_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
mkdir -p "${FIREFOX_PROFILE_BASE}/emoncms.profile"

cat > "${FIREFOX_PROFILE_BASE}/profiles.ini" << 'PROFILES_EOF'
[Profile0]
Name=emoncms
IsRelative=1
Path=emoncms.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES_EOF

cat > "${FIREFOX_PROFILE_BASE}/emoncms.profile/user.js" << 'USER_JS_EOF'
user_pref("browser.startup.homepage", "http://localhost/user/login");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.autoDisableScopes", 15);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("privacy.notices.shown", true);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.firstrunSkipsHomepage", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("signon.management.page.breach-alerts.enabled", false);
user_pref("signon.autofillForms", false);
user_pref("signon.rememberSignons", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.vpn_promo.enabled", false);
USER_JS_EOF

chown -R ga:ga /home/ga/snap/ 2>/dev/null || true

# -----------------------------------------------------------------------
# 9. Re-verify Emoncms is still responsive after seeding, then launch Firefox
# -----------------------------------------------------------------------
echo "Re-verifying Emoncms is responsive before launching Firefox..."
for i in $(seq 1 60); do
    if curl -s -o /dev/null -w "%{http_code}" "${EMONCMS_URL}/" 2>/dev/null | grep -qE "200|302|301"; then
        echo "Emoncms web service ready"
        break
    fi
    sleep 2
done

pkill -9 -f firefox 2>/dev/null || true

for i in $(seq 1 10); do
    pgrep -f firefox >/dev/null 2>&1 || break
    sleep 1
done

rm -f "${FIREFOX_PROFILE_BASE}/emoncms.profile/.parentlock" \
      "${FIREFOX_PROFILE_BASE}/emoncms.profile/lock" 2>/dev/null || true

sleep 2

su - ga -c "
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/emoncms.profile/.parentlock \
          /home/ga/snap/firefox/common/.mozilla/firefox/emoncms.profile/lock 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=${XAUTH} \
    setsid firefox --new-instance \
        -profile /home/ga/snap/firefox/common/.mozilla/firefox/emoncms.profile \
        'http://localhost/user/login' &
"

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -qi "firefox"; then
        echo "Firefox window appeared"
        break
    fi
    sleep 2
done
sleep 3

# Maximize Firefox window
DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
    -b add,maximized_vert,maximized_horz 2>/dev/null || true

# -----------------------------------------------------------------------
# 10. Log in to Emoncms in Firefox
#     NOTE: Emoncms login is AJAX-based (user.js calls /user/login.json).
#     The login form has autofocus on the username field.
# -----------------------------------------------------------------------
echo "Logging in to Emoncms as admin..."
sleep 5

# Wait for login page to load
for i in $(seq 1 20); do
    PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$PAGE_TITLE" | grep -qi "login\|firefox"; then
        echo "Firefox login page ready: $PAGE_TITLE"
        break
    fi
    sleep 1
done
sleep 3

# Dismiss any first-run popups
DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to login page in address bar
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key ctrl+l"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'http://localhost/user/login'"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return"
sleep 4

# Dismiss any dialogs (Firefox sidebar popup etc.)
DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool key Escape 2>/dev/null || true
sleep 1

# Username field has autofocus on login page
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'admin'"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'admin'"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return"
sleep 5

# Navigate to feeds page after login
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'http://localhost/feed/list'"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return"
sleep 3

# Take a screenshot to verify setup
DISPLAY=:1 XAUTHORITY="${XAUTH}" xwd -root -silent -out /tmp/emoncms_setup.xwd 2>/dev/null \
    && convert /tmp/emoncms_setup.xwd /tmp/emoncms_setup_screenshot.png 2>/dev/null \
    && rm -f /tmp/emoncms_setup.xwd || true

echo "=== Emoncms setup complete ==="
echo "=== Application URL: http://localhost ==="
echo "=== Admin credentials: admin / admin ==="
echo "=== Write API key: ${ADMIN_APIKEY_WRITE} ==="
