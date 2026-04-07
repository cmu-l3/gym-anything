#!/bin/bash
set -e

echo "=== Setting up Odoo HR Environment ==="

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_hr"
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
# Step 2: Initialize Odoo database with HR modules
# Modules: hr (employees/departments/jobs), hr_holidays (time off),
#          hr_expense (expenses), hr_recruitment (recruitment)
# Demo data is loaded (no --without-demo flag) — Odoo official sample data
# (20 employees, 7 departments, 6 leave types, leave allocations, demo expenses).
# setup_data.py adds only 2 supplementary leave requests (Rachel Perry, Doris Cole).
# -------------------------------------------------------
echo "Initializing Odoo database with HR modules and official demo data (this takes 10-15 minutes)..."
cd "$ODOO_DIR"
docker compose run --rm --no-deps odoo odoo \
    -d "$ODOO_DB" \
    -i hr,hr_holidays,hr_expense,hr_recruitment \
    --db_host=db \
    --db_user=odoo \
    --db_password=odoo \
    --stop-after-init \
    2>&1 | tail -50
# NOTE: Demo data is Odoo's official sample database (20 real employees, departments, jobs,
# leave types, allocations, expenses). This is the recommended approach per prompt.md.

# Verify database was created
sleep 3
DB_EXISTS=$(docker exec odoo-db psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$ODOO_DB'" 2>/dev/null | tr -d '[:space:]')

if [ "$DB_EXISTS" != "1" ]; then
    echo "WARNING: Database '$ODOO_DB' not found after init. Retrying..."
    docker compose run --rm --no-deps odoo odoo \
        -d "$ODOO_DB" \
        -i hr,hr_holidays,hr_expense,hr_recruitment \
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
        -i hr,hr_holidays,hr_expense,hr_recruitment \
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
# Step 4: Create realistic HR data via RPC
# -------------------------------------------------------
echo "Creating HR data via Odoo RPC..."
python3 /workspace/scripts/setup_data.py

# -------------------------------------------------------
# Step 5: Configure Firefox profile via headless warm-up
# Creates auto-generated .default* profile, injects user.js
# to suppress first-run dialogs.
# -------------------------------------------------------
echo "Configuring Firefox profile via headless warm-up..."

su - ga -c "DISPLAY=:1 firefox --headless about:blank > /dev/null 2>&1 &" || true
sleep 12
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Find the auto-generated snap default profile
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "Found Firefox profile at: $SNAP_PROFILE_DIR"
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
# Step 6: Flush data to disk
# -------------------------------------------------------
echo "Flushing data to disk..."
docker exec odoo-db psql -U odoo -d postgres -c "CHECKPOINT" 2>/dev/null || true
sync
echo "Disk sync complete."

# -------------------------------------------------------
# Step 7: Final status
# -------------------------------------------------------
echo "=== Odoo HR setup complete ==="
echo "URL: http://localhost:8069"
echo "Database: $ODOO_DB"
echo "Admin login: admin / admin"
echo "Installed modules: hr, hr_holidays, hr_expense, hr_recruitment"
echo "Firefox will be launched by pre_task hooks (ensure_firefox)"
