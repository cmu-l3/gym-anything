#!/bin/bash
# Odoo Setup Script (post_start hook)
# Starts Odoo via Docker and launches Firefox
#
# Default credentials: admin / admin
# URL: http://localhost:8069

echo "=== Setting up Odoo via Docker ==="

# Configuration
ODOO_URL="http://localhost:8069"
ODOO_DB_NAME="odoo_demo"
ADMIN_EMAIL="admin"
ADMIN_PASS="admin"

# Copy docker-compose.yml to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/odoo
cp /workspace/config/docker-compose.yml /home/ga/odoo/
chown -R ga:ga /home/ga/odoo

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
    systemctl start docker
    sleep 5
fi

cd /home/ga/odoo

# Clean up any existing containers/volumes from previous runs
docker compose down -v 2>/dev/null || true
sleep 3

# ===== Step 1: Start PostgreSQL ONLY =====
echo "Starting PostgreSQL..."
docker compose up -d postgres

# Wait for PostgreSQL to be healthy
echo "Waiting for PostgreSQL to be ready..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker exec odoo-postgres pg_isready -U odoo 2>/dev/null; then
        echo "PostgreSQL is ready after ${elapsed}s"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
done

if [ $elapsed -ge $timeout ]; then
    echo "ERROR: PostgreSQL did not start in time"
    docker compose logs postgres
    exit 1
fi

# ===== Step 2: Initialize database BEFORE starting web service =====
echo "Initializing Odoo database with demo data (this takes 5-15 minutes)..."
docker compose run --rm --no-deps odoo odoo \
    -d "$ODOO_DB_NAME" \
    -i base \
    --db_host=postgres \
    --db_user=odoo \
    --db_password=odoo \
    --load-language=en_US \
    --stop-after-init \
    2>&1 | tee /tmp/odoo_init.log | tail -50

# Verify database was created
sleep 3
DB_EXISTS=$(docker exec odoo-postgres psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$ODOO_DB_NAME'" 2>/dev/null | tr -d '[:space:]')

if [ "$DB_EXISTS" != "1" ]; then
    echo "WARNING: Database '$ODOO_DB_NAME' not found after init. Retrying..."
    docker compose run --rm --no-deps odoo odoo \
        -d "$ODOO_DB_NAME" \
        -i base \
        --db_host=postgres \
        --db_user=odoo \
        --db_password=odoo \
        --stop-after-init \
        2>&1 | tail -30
    sleep 3
fi

# Verify base module is installed
BASE_INSTALLED=$(docker exec odoo-postgres psql -U odoo -d "$ODOO_DB_NAME" -tAc \
    "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "Base module installed: ${BASE_INSTALLED:-0}"

if [ "${BASE_INSTALLED:-0}" -lt "1" ]; then
    echo "ERROR: Base module not installed. Retrying from scratch..."
    docker exec odoo-postgres psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS $ODOO_DB_NAME" 2>/dev/null || true
    sleep 2
    docker compose run --rm --no-deps odoo odoo \
        -d "$ODOO_DB_NAME" \
        -i base \
        --db_host=postgres \
        --db_user=odoo \
        --db_password=odoo \
        --stop-after-init \
        2>&1 | tail -30
fi

echo "Database initialization complete"

# ===== Step 3: Start Odoo web service =====
echo "Starting Odoo web service..."
docker compose up -d odoo

# Wait for Odoo web to respond
echo "Waiting for Odoo web service..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/login" 2>/dev/null || echo "0")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ]; then
        echo "Odoo web is ready (HTTP $HTTP_CODE) after ${elapsed}s"
        break
    fi
    echo "  Waiting... HTTP $HTTP_CODE ($elapsed/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    echo "WARNING: Odoo web did not become ready in time"
    docker compose logs odoo | tail -30
fi

# ===== Step 4: Verify Odoo is not returning 500 =====
sleep 5
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/login" 2>/dev/null || echo "000")
echo "Odoo HTTP status at /web/login: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "500" ]; then
    echo "Odoo returning 500 - attempting web service restart..."
    docker compose restart odoo
    sleep 20
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/login" 2>/dev/null || echo "000")
    echo "After restart: HTTP $HTTP_STATUS"
fi

# ===== Step 5: Set up Firefox profile =====
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost:8069/web/login?db=odoo_demo");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Odoo.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Odoo ERP
Comment=Enterprise Resource Planning
Exec=firefox http://localhost:8069/web/login?db=odoo_demo
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Business;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Odoo.desktop
chmod +x /home/ga/Desktop/Odoo.desktop

# Create utility script for database queries
cat > /usr/local/bin/odoo-db-query << 'DBQUERYEOF'
#!/bin/bash
docker exec odoo-postgres psql -U odoo -d odoo_demo -t -A -c "$1"
DBQUERYEOF
chmod +x /usr/local/bin/odoo-db-query

# ===== Step 6: Launch Firefox =====
echo "Launching Firefox with Odoo..."
su - ga -c "DISPLAY=:1 firefox '$ODOO_URL/web/login?db=$ODOO_DB_NAME' > /tmp/firefox_odoo.log 2>&1 &"

sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|odoo"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== Odoo Setup Complete ==="
echo "URL: $ODOO_URL"
echo "Login: $ADMIN_EMAIL / $ADMIN_PASS"
echo "Database: $ODOO_DB_NAME"

# Flush all data to disk for checkpoint consistency
echo "Flushing data to disk..."
docker exec odoo-postgres psql -U odoo -d postgres -c "CHECKPOINT" 2>/dev/null || true
sync
echo "Disk sync complete."
