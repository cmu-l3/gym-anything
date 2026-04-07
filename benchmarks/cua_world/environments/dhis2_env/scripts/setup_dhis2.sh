#!/bin/bash
# DHIS2 Setup Script (post_start hook)
# Starts DHIS2 via Docker with Sierra Leone demo database and launches Firefox
#
# Default credentials: admin / district

echo "=== Setting up DHIS2 via Docker ==="

# Configuration
DHIS2_URL="http://localhost:8080"
DHIS2_LOGIN_URL="http://localhost:8080/dhis-web-commons/security/login.action"
ADMIN_USER="admin"
ADMIN_PASS="district"
DEMO_DB_URL="https://databases.dhis2.org/sierra-leone/2.40/dhis2-db-sierra-leone.sql.gz"
DEMO_DB_ALT_URL="https://databases.dhis2.org/sierra-leone/2.40.11/dhis2-db-sierra-leone.sql.gz"

# Function to wait for DHIS2 to be ready
wait_for_dhis2() {
    local timeout=${1:-600}
    local elapsed=0

    echo "Waiting for DHIS2 to be ready (this may take several minutes on first run)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if the login page returns HTTP 200
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$DHIS2_LOGIN_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo "DHIS2 is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        # Also check the API endpoint
        HTTP_CODE_API=$(curl -s -o /dev/null -w "%{http_code}" "$DHIS2_URL/api/system/info" 2>/dev/null)
        if [ "$HTTP_CODE_API" = "200" ] || [ "$HTTP_CODE_API" = "401" ] || [ "$HTTP_CODE_API" = "302" ]; then
            echo "DHIS2 API is responding after ${elapsed}s (HTTP $HTTP_CODE_API)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting... ${elapsed}s (login=$HTTP_CODE, api=$HTTP_CODE_API)"
    done

    echo "WARNING: DHIS2 readiness check timed out after ${timeout}s"
    return 1
}

# Copy docker-compose.yml and dhis.conf to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/dhis2
cp /workspace/config/docker-compose.yml /home/ga/dhis2/
cp /workspace/config/dhis.conf /home/ga/dhis2/
chmod 644 /home/ga/dhis2/dhis.conf
chown -R ga:ga /home/ga/dhis2

cd /home/ga/dhis2

# Step 1: Start only the database container first
echo "Starting PostgreSQL database container..."
docker-compose up -d db

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker exec dhis2-db pg_isready -U dhis -d dhis2 2>/dev/null; then
        echo "PostgreSQL is ready after ${ELAPSED}s"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  Waiting for PostgreSQL... ${ELAPSED}s"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: PostgreSQL did not become ready within ${TIMEOUT}s"
    docker-compose logs db
    exit 1
fi

# Step 2: Download and import Sierra Leone demo database
echo ""
echo "Downloading Sierra Leone demo database..."
echo "This is official real-world demo data from the DHIS2 project."

DEMO_DB_FILE="/tmp/dhis2-db-sierra-leone.sql.gz"

# Try primary URL first, then alternative
if ! wget -q --show-progress -O "$DEMO_DB_FILE" "$DEMO_DB_URL" 2>/dev/null; then
    echo "Primary URL failed, trying alternative..."
    if ! wget -q --show-progress -O "$DEMO_DB_FILE" "$DEMO_DB_ALT_URL" 2>/dev/null; then
        echo "ERROR: Could not download Sierra Leone demo database"
        echo "Tried: $DEMO_DB_URL"
        echo "Tried: $DEMO_DB_ALT_URL"
        echo "DHIS2 will start with an empty database."
        DEMO_DB_FILE=""
    fi
fi

if [ -n "$DEMO_DB_FILE" ] && [ -f "$DEMO_DB_FILE" ]; then
    echo "Demo database downloaded. Importing into PostgreSQL..."

    # Copy the gzipped SQL to the database container
    docker cp "$DEMO_DB_FILE" dhis2-db:/tmp/dhis2-db-sierra-leone.sql.gz

    # Decompress and import
    echo "Decompressing and importing (this may take a few minutes)..."
    docker exec dhis2-db bash -c "gunzip -c /tmp/dhis2-db-sierra-leone.sql.gz | psql -U dhis -d dhis2 -q" 2>&1 | tail -5

    # Verify import
    TABLE_COUNT=$(docker exec dhis2-db psql -U dhis -d dhis2 -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null | tr -d ' ')
    echo "Database tables created: $TABLE_COUNT"

    # Check for key tables
    OU_COUNT=$(docker exec dhis2-db psql -U dhis -d dhis2 -t -c "SELECT COUNT(*) FROM organisationunit" 2>/dev/null | tr -d ' ')
    echo "Organisation units: $OU_COUNT"

    # Clean up
    docker exec dhis2-db rm -f /tmp/dhis2-db-sierra-leone.sql.gz
    rm -f "$DEMO_DB_FILE"

    echo "Sierra Leone demo database imported successfully!"
else
    echo "Skipping demo database import."
fi

# Step 3: Start the DHIS2 application container
echo ""
echo "Starting DHIS2 application container..."
docker-compose up -d dhis2

echo "Containers starting..."
docker-compose ps

# Step 4: Wait for DHIS2 to be fully ready
wait_for_dhis2 900

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Step 5: Set up Firefox profile for user 'ga'
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create Firefox profiles.ini
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

# Create user.js to configure Firefox (disable first-run dialogs, etc.)
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to DHIS2
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

# Set ownership of Firefox profile
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/DHIS2.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=DHIS2
Comment=District Health Information Software
Exec=firefox http://localhost:8080
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Medical;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/DHIS2.desktop
chmod +x /home/ga/Desktop/DHIS2.desktop
# Mark desktop file as trusted to prevent GNOME "Untrusted Desktop File" dialog
su - ga -c "dbus-launch gio set /home/ga/Desktop/DHIS2.desktop metadata::trusted true" 2>/dev/null || true

# Create utility script for database queries
cat > /usr/local/bin/dhis2-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against DHIS2 database (via Docker)
docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1"
DBQUERYEOF
chmod +x /usr/local/bin/dhis2-db-query

# Create utility script for DHIS2 API calls
cat > /usr/local/bin/dhis2-api << 'APIEOF'
#!/bin/bash
# Execute DHIS2 API call
curl -s -u admin:district "http://localhost:8080/api/$1"
APIEOF
chmod +x /usr/local/bin/dhis2-api

# Start Firefox for the ga user
echo "Launching Firefox with DHIS2..."
su - ga -c "DISPLAY=:1 firefox '$DHIS2_LOGIN_URL' > /tmp/firefox_dhis2.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|dhis"; then
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
echo "=== DHIS2 Setup Complete ==="
echo ""
echo "DHIS2 is running at: http://localhost:8080/"
echo ""
echo "Login Credentials:"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "Database access (via Docker):"
echo "  dhis2-db-query \"SELECT COUNT(*) FROM organisationunit\""
echo ""
echo "API access:"
echo "  dhis2-api \"system/info\""
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/dhis2/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/dhis2/docker-compose.yml ps"
echo ""
