#!/bin/bash
set -e

echo "=== Setting up Odoo Quality Environment ==="

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_quality"
ODOO_DIR="/opt/odoo"

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
    systemctl start docker
    sleep 5
fi

# -------------------------------------------------------
# Step 0: Copy custom addons to /opt/odoo/addons
# These will be mounted into the Odoo container as /mnt/extra-addons
# -------------------------------------------------------
echo "Copying custom Odoo addons..."
mkdir -p "$ODOO_DIR/addons"
cp -r /workspace/addons/quality "$ODOO_DIR/addons/"
cp -r /workspace/addons/quality_control "$ODOO_DIR/addons/"
# CRITICAL: chmod 755 so the Odoo container user (odoo, non-root) can read these
chmod -R 755 "$ODOO_DIR/addons/"
echo "Custom addons copied to $ODOO_DIR/addons/"

# -------------------------------------------------------
# Step 1: Start PostgreSQL
# -------------------------------------------------------
echo "Starting PostgreSQL..."
cd "$ODOO_DIR"
docker compose up -d db

# Wait for PostgreSQL to be healthy
echo "Waiting for PostgreSQL to be ready..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker exec odoo-db pg_isready -U odoo 2>/dev/null; then
        echo "PostgreSQL is ready"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
done

if [ $elapsed -ge $timeout ]; then
    echo "ERROR: PostgreSQL did not start in time"
    docker compose logs db
    exit 1
fi

# -------------------------------------------------------
# Step 2: Initialize Odoo database with Quality modules
# quality_control auto-installs stock, quality, and other dependencies.
# Skip demo data: Odoo 17 purchase demo data has a MissingError bug that
# crashes init. setup_data.py provides all task-specific data instead.
# -------------------------------------------------------
echo "Initializing Odoo database with quality_control module (this takes 5-10 minutes)..."
cd "$ODOO_DIR"
docker compose run --rm --no-deps odoo odoo \
    -d "$ODOO_DB" \
    -i quality_control \
    --db_host=db \
    --db_user=odoo \
    --db_password=odoo \
    --without-demo all \
    --stop-after-init \
    2>&1 | tail -50

echo "Database initialization complete"

# -------------------------------------------------------
# Step 3: Start Odoo web service
# -------------------------------------------------------
echo "Starting Odoo web service..."
cd "$ODOO_DIR"
docker compose up -d odoo

# Wait for Odoo web to respond
echo "Waiting for Odoo web service..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/health" 2>/dev/null || echo "0")
    if [ "$http_code" = "200" ]; then
        echo "Odoo web is ready (HTTP $http_code)"
        break
    fi
    echo "  Waiting... HTTP $http_code ($elapsed/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Odoo web did not start in time"
    docker compose logs odoo | tail -30
    exit 1
fi

sleep 10

# -------------------------------------------------------
# Step 4: Create quality-specific data via RPC
# -------------------------------------------------------
echo "Creating quality data via Odoo RPC..."
python3 /workspace/scripts/setup_data.py

# -------------------------------------------------------
# Step 5: Configure Firefox profile via headless warm-up
# This creates the auto-generated .default* profile that snap Firefox
# uses, then injects user.js to suppress first-run dialogs.
# IMPORTANT: Do NOT create custom profiles.ini or custom profile dirs —
# that causes blank rendering with snap Firefox (odoo_crm_env lesson).
# Firefox is killed here; pre_task hooks launch it fresh from snapshot.
# -------------------------------------------------------
echo "Configuring Firefox profile via headless warm-up..."

# Headless warm-up: snap Firefox creates auto-generated .default* profile
su - ga -c "DISPLAY=:1 firefox --headless about:blank > /dev/null 2>&1 &" || true
sleep 12
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Find the auto-generated snap default profile
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    # Fallback: non-snap Firefox profile path
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "Found Firefox profile at: $SNAP_PROFILE_DIR"
    # Inject user.js — only first-run suppression prefs
    # DO NOT add dom.ipc.processCount, gfx.webrender.enabled or similar
    # renderer overrides — these cause blank pages with snap Firefox
    cat > "$SNAP_PROFILE_DIR/user.js" << 'USERJS_EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.startup.page", 0);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
user_pref("app.update.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
USERJS_EOF
    chown ga:ga "$SNAP_PROFILE_DIR/user.js"
    echo "user.js written to Firefox profile: $SNAP_PROFILE_DIR"
else
    echo "WARNING: Could not find Firefox default profile directory after headless warm-up"
fi

# -------------------------------------------------------
# Step 6: Final status
# -------------------------------------------------------
echo "=== Odoo Quality setup complete ==="
echo "URL: http://localhost:8069"
echo "Database: $ODOO_DB"
echo "Admin login: admin / admin"
echo "Installed modules: quality_control (custom), quality (custom), stock"
echo "Firefox will be launched by pre_task hooks (ensure_firefox)"
