#!/bin/bash
set -e

echo "=== Setting up Odoo Scheduling Environment ==="

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_scheduling"
ODOO_DIR="/opt/odoo"

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
    systemctl start docker
    sleep 5
fi

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
# Step 2: Initialize Odoo database with Calendar module
# Note: 'appointment' is Enterprise-only; use calendar + contacts
# -------------------------------------------------------
echo "Initializing Odoo database (this takes 5-10 minutes)..."
cd "$ODOO_DIR"
docker compose run --rm --no-deps odoo odoo \
    -d "$ODOO_DB" \
    -i calendar,contacts \
    --db_host=db \
    --db_user=odoo \
    --db_password=odoo \
    --stop-after-init \
    2>&1 | tail -20

# Verify database was created
sleep 3
DB_EXISTS=$(docker exec odoo-db psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$ODOO_DB'" 2>/dev/null | tr -d '[:space:]')

if [ "$DB_EXISTS" != "1" ]; then
    echo "WARNING: Database '$ODOO_DB' not found after init. Retrying..."
    docker compose run --rm --no-deps odoo odoo \
        -d "$ODOO_DB" \
        -i calendar,contacts \
        --db_host=db \
        --db_user=odoo \
        --db_password=odoo \
        --stop-after-init \
        2>&1 | tail -30
    sleep 3
fi

# Verify base module is installed
BASE_INSTALLED=$(docker exec odoo-db psql -U odoo -d "$ODOO_DB" -tAc \
    "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "Base module installed: ${BASE_INSTALLED:-0}"

if [ "${BASE_INSTALLED:-0}" -lt "1" ]; then
    echo "ERROR: Base module not installed. Retrying from scratch..."
    docker exec odoo-db psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS $ODOO_DB" 2>/dev/null || true
    sleep 2
    docker compose run --rm --no-deps odoo odoo \
        -d "$ODOO_DB" \
        -i calendar,contacts \
        --db_host=db \
        --db_user=odoo \
        --db_password=odoo \
        --stop-after-init \
        2>&1 | tail -30
fi

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
# Step 4: Create realistic contacts and calendar events via RPC
# -------------------------------------------------------
echo "Creating contacts and calendar events via Odoo RPC..."
python3 /workspace/scripts/setup_data.py

# -------------------------------------------------------
# Step 5: Configure Firefox profile
# -------------------------------------------------------
echo "Configuring Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/odoo.profile"
mkdir -p "$FIREFOX_PROFILE_DIR"

cat > "$FIREFOX_PROFILE_DIR/user.js" << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("app.update.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("extensions.shield-recipe-client.api_url", "");
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
EOF

cat > "/home/ga/.mozilla/firefox/profiles.ini" << 'EOF'
[Profile0]
Name=odoo
IsRelative=1
Path=odoo.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

chown -R ga:ga /home/ga/.mozilla

# -------------------------------------------------------
# Step 6: Flush data to disk
# -------------------------------------------------------
echo "Flushing data to disk..."
docker exec odoo-db psql -U odoo -d postgres -c "CHECKPOINT" 2>/dev/null || true
sync
echo "Disk sync complete."

# -------------------------------------------------------
# Step 7: Final status
# NOTE: Firefox is NOT launched here. Snap Firefox survives
# VM snapshot/restore poorly: the process crashes on restore
# and leaves a stale snap lock, causing the "Close Firefox"
# dialog on next launch. Instead, each pre_task hook launches
# Firefox fresh via ensure_firefox() which is always the
# first-ever launch from the savevm snapshot — no snap lock.
# -------------------------------------------------------
echo "=== Odoo Scheduling setup complete ==="
echo "URL: http://localhost:8069"
echo "Database: $ODOO_DB"
echo "Admin login: admin / admin"
echo "Firefox will be launched by pre_task hooks (ensure_firefox)"
