#!/bin/bash
set -e

echo "=== Setting up Odoo CRM ==="

# Wait for desktop
sleep 5

# ===== Prepare working directory =====
mkdir -p /home/ga/odoo/addons
cp /workspace/config/docker-compose.yml /home/ga/odoo/docker-compose.yml
cp /workspace/config/odoo.conf /home/ga/odoo/odoo.conf
chown -R ga:ga /home/ga/odoo

# ===== Docker Hub authentication (if credentials available) =====
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# ===== Pull images =====
cd /home/ga/odoo
echo "Pulling Docker images..."
docker compose pull || {
    echo "Pull failed (rate limit?), proceeding with cached images if available"
}

# ===== Start PostgreSQL first =====
echo "Starting PostgreSQL..."
docker compose up -d db

# Wait for PostgreSQL to be ready
wait_for_postgres() {
    local timeout=120
    local elapsed=0
    echo "Waiting for PostgreSQL..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec odoo-db pg_isready -U odoo > /dev/null 2>&1; then
            echo "PostgreSQL ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: PostgreSQL not ready after ${timeout}s"
    return 1
}
wait_for_postgres

# ===== Initialize Odoo database with CRM module and demo data =====
echo "Initializing Odoo database (this may take 8-15 minutes)..."
cd /home/ga/odoo
docker compose run --rm web odoo \
    --stop-after-init \
    -d odoodb \
    -i crm,contacts,mail \
    --db_host=db \
    --db_user=odoo \
    --db_password=odoo \
    2>&1 | tail -20 || {
    echo "WARNING: Odoo init returned non-zero exit code, checking if DB was created..."
}

# Verify database was created
sleep 3
if docker exec odoo-db psql -U odoo -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw odoodb; then
    echo "Database 'odoodb' created successfully"
else
    echo "ERROR: Database 'odoodb' not found after initialization"
    docker exec odoo-db psql -U odoo -lqt 2>/dev/null || true
    exit 1
fi

# ===== Start Odoo web service =====
echo "Starting Odoo web service..."
cd /home/ga/odoo
docker compose up -d web

# Wait for Odoo to be ready
wait_for_odoo() {
    local timeout=300
    local elapsed=0
    echo "Waiting for Odoo web service..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8069/web/login 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Odoo ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "ERROR: Odoo not ready after ${timeout}s, last HTTP code: $HTTP_CODE"
    return 1
}
wait_for_odoo

# ===== Seed additional CRM data =====
echo "Seeding CRM data..."
sleep 5
python3 /workspace/data/seed_crm.py || {
    echo "WARNING: CRM seeding failed, continuing..."
}

# ===== Set up Firefox profile (suppress first-run dialogs) =====
# Warm-up headless launch to let Firefox snap create its default profile
echo "Creating Firefox snap default profile..."
su - ga -c "DISPLAY=:1 firefox --headless &"
sleep 10
pkill -f firefox 2>/dev/null || true
sleep 2

# Find the auto-generated snap default profile
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    # Fallback: non-snap Firefox
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "Found Firefox profile at: $SNAP_PROFILE_DIR"
    cat > "$SNAP_PROFILE_DIR/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "http://localhost:8069/web/login");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.feeds.showFirstRunUI", false);
user_pref("browser.uitour.enabled", false);
FFEOF
    chown ga:ga "$SNAP_PROFILE_DIR/user.js"
    echo "user.js written to Firefox snap profile"
else
    echo "WARNING: Could not find Firefox default profile"
fi

# ===== Warm-up: Launch Firefox and log into Odoo =====
echo "Warming up Firefox..."
su - ga -c "DISPLAY=:1 firefox http://localhost:8069/web/login &"
sleep 15

# Login to Odoo (verified coordinates for 1920x1080)
# Email at actual(993, 422), Password at actual(993, 503), Login at actual(993, 569)
DISPLAY=:1 xdotool mousemove 993 422 click 1 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type "admin"

DISPLAY=:1 xdotool mousemove 993 503 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type "admin"

DISPLAY=:1 xdotool mousemove 993 569 click 1 2>/dev/null || true
sleep 8

echo "Warm-up login complete"

echo "=== Odoo CRM setup complete ==="
