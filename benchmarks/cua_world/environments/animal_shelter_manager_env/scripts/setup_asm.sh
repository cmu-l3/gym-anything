#!/bin/bash
# Animal Shelter Manager 3 Setup Script (post_start hook)
# Starts ASM3, initializes database, imports real data, launches Firefox
#
# Default credentials: user / letmein

set -e

echo "=== Setting up Animal Shelter Manager 3 ==="

ASM_URL="http://localhost:8080"
ASM_LOGIN_URL="${ASM_URL}/login"
ASM_DB_URL="${ASM_URL}/database"
ASM_DIR="/opt/asm3/src"
ADMIN_USER="user"
ADMIN_PASS="letmein"

# Wait for desktop to be ready
sleep 5

# Ensure PostgreSQL is running
echo "Ensuring PostgreSQL is running..."
systemctl start postgresql
for i in {1..30}; do
    if su - postgres -c "pg_isready" 2>/dev/null; then
        echo "PostgreSQL is ready"
        break
    fi
    sleep 1
done

# Ensure ASM3 config is in place
cp /workspace/config/asm3.conf "${ASM_DIR}/asm3.conf"

# Start ASM3 application
echo "Starting ASM3 application..."
cd "${ASM_DIR}"
nohup python3 main.py > /tmp/asm3_app.log 2>&1 &
ASM_PID=$!
echo "ASM3 started with PID ${ASM_PID}"

# Wait for ASM3 to be ready
wait_for_asm() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for ASM3 to be ready..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${ASM_URL}/login" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "ASM3 is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        # Also check the database setup page
        HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" "${ASM_DB_URL}" 2>/dev/null)
        if [ "$HTTP_CODE2" = "200" ]; then
            echo "ASM3 database page ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        echo "  Waiting... ${elapsed}s (login: HTTP $HTTP_CODE, db: HTTP $HTTP_CODE2)"
    done

    echo "WARNING: ASM3 readiness check timed out after ${timeout}s"
    echo "ASM3 log:"
    tail -30 /tmp/asm3_app.log 2>/dev/null || true
    return 1
}

wait_for_asm 120

# Initialize the database schema via ASM3's database endpoint
echo "Initializing ASM3 database..."
# Check if database is already initialized
DB_READY=$(PGPASSWORD=asm psql -h localhost -U asm -d asm -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='configuration'" 2>/dev/null | tr -d ' ')
if [ "$DB_READY" = "1" ]; then
    echo "Database schema already initialized"
else
    echo "Creating database schema via HTTP POST..."
    curl -s --max-time 180 -X POST "${ASM_DB_URL}" \
        -d "action=create" \
        -d "dbtype=POSTGRESQL" \
        -d "host=localhost" \
        -d "port=5432" \
        -d "username=asm" \
        -d "password=asm" \
        -d "database=asm" \
        -d "locale=en" 2>/dev/null || true
    sleep 5
    echo "Database schema created"
fi

# Import real animal shelter data
echo "Importing real animal shelter data..."
if [ -f /workspace/data/import_real_data.py ]; then
    python3 /workspace/data/import_real_data.py 2>&1 || echo "Data import had issues, continuing..."
else
    echo "No import script found, skipping data import"
fi

# Suppress the welcome popup that shows on first login
echo "Configuring ASM3 to suppress welcome popup..."
PGPASSWORD=asm psql -h localhost -U asm -d asm -c "INSERT INTO configuration (ItemName, ItemValue) VALUES ('ShowFirstTime', 'No') ON CONFLICT DO NOTHING" 2>/dev/null || true
PGPASSWORD=asm psql -h localhost -U asm -d asm -c "UPDATE configuration SET ItemValue = 'No' WHERE ItemName = 'ShowFirstTime'" 2>/dev/null || true

# Restart ASM3 after data import to ensure clean state
echo "Restarting ASM3..."
kill $ASM_PID 2>/dev/null || true
sleep 2
cd "${ASM_DIR}"
nohup python3 main.py > /tmp/asm3_app.log 2>&1 &
wait_for_asm 60

# Set up Firefox profile
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
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to ASM3
user_pref("browser.startup.homepage", "http://localhost:8080");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and other popups
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
cat > /home/ga/Desktop/ASM3.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Animal Shelter Manager
Comment=Animal Shelter Management System
Exec=firefox http://localhost:8080
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/ASM3.desktop
chmod +x /home/ga/Desktop/ASM3.desktop

# Create utility script for database queries
cat > /usr/local/bin/asm-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against ASM3 PostgreSQL database
PGPASSWORD=asm psql -h localhost -U asm -d asm -t -c "$1"
DBQUERYEOF
chmod +x /usr/local/bin/asm-db-query

# Launch Firefox for the ga user
echo "Launching Firefox with ASM3..."
su - ga -c "DISPLAY=:1 firefox '${ASM_LOGIN_URL}' > /tmp/firefox_asm.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|shelter"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== Animal Shelter Manager Setup Complete ==="
echo ""
echo "ASM3 is running at: ${ASM_URL}"
echo ""
echo "Login Credentials:"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "Database access:"
echo "  asm-db-query \"SELECT COUNT(*) FROM animal\""
echo ""
