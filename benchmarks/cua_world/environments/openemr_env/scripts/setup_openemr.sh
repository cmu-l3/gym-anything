#!/bin/bash
# OpenEMR Setup Script (post_start hook)
# Starts OpenEMR via Docker and launches Firefox
#
# Default credentials: admin / pass

echo "=== Setting up OpenEMR via Docker ==="

# Configuration
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"
ADMIN_USER="admin"
ADMIN_PASS="pass"

# Function to wait for OpenEMR to be ready
wait_for_openemr() {
    local timeout=${1:-180}
    local elapsed=0

    echo "Waiting for OpenEMR to be ready (this may take a few minutes on first run)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if the login page returns HTTP 200
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OPENEMR_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo "OpenEMR is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: OpenEMR readiness check timed out after ${timeout}s"
    return 1
}

# Copy docker-compose.yml to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/openemr
cp /workspace/config/docker-compose.yml /home/ga/openemr/
chown -R ga:ga /home/ga/openemr

# Start OpenEMR containers
echo "Starting OpenEMR Docker containers..."
cd /home/ga/openemr

# Pull images first (better error handling)
docker-compose pull

# Start containers in detached mode
docker-compose up -d

echo "Containers starting..."
docker-compose ps

# Wait for OpenEMR to be fully ready
wait_for_openemr 180

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Load Synthea patient data if available
PATIENT_DATA="/workspace/config/sample_patients.sql"
if [ -f "$PATIENT_DATA" ]; then
    echo ""
    echo "Loading Synthea patient data..."

    # Copy SQL file to MySQL container
    docker cp "$PATIENT_DATA" openemr-mysql:/tmp/sample_patients.sql

    # Import the data (suppress warnings about duplicate keys)
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "source /tmp/sample_patients.sql" 2>&1 | grep -v "Duplicate entry" | head -20

    # Verify import
    PATIENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM patient_data" 2>/dev/null)
    echo "Loaded patients: $PATIENT_COUNT"

    # Clean up
    docker exec openemr-mysql rm -f /tmp/sample_patients.sql

    echo "Synthea patient data loaded successfully!"
else
    echo "Note: sample_patients.sql not found, using default OpenEMR data"
fi

# Set up Firefox profile for user 'ga'
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

// Set homepage to OpenEMR
user_pref("browser.startup.homepage", "http://localhost/interface/login/login.php?site=default");
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
cat > /home/ga/Desktop/OpenEMR.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=OpenEMR
Comment=Electronic Health Records
Exec=firefox http://localhost/interface/login/login.php?site=default
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Medical;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OpenEMR.desktop
chmod +x /home/ga/Desktop/OpenEMR.desktop

# Create utility script for database queries
cat > /usr/local/bin/openemr-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against OpenEMR database (via Docker)
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/openemr-db-query

# Start Firefox for the ga user
echo "Launching Firefox with OpenEMR..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_openemr.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
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
echo "=== OpenEMR Setup Complete ==="
echo ""
echo "OpenEMR is running at: http://localhost/"
echo ""
echo "Login Credentials:"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "Database access (via Docker):"
echo "  openemr-db-query \"SELECT COUNT(*) FROM patient_data\""
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/openemr/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/openemr/docker-compose.yml ps"
echo ""
