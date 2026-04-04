#!/bin/bash
# Odoo Setup Script (post_start hook)
# Starts Odoo via Docker and launches Firefox
#
# Default database credentials: admin / admin (set during database creation)

echo "=== Setting up Odoo via Docker ==="

# Configuration
ODOO_URL="http://localhost:8069"
ODOO_DB_NAME="odoo_demo"
ADMIN_EMAIL="admin@example.com"
ADMIN_PASS="admin"

# Function to wait for Odoo to be ready
wait_for_odoo() {
    local timeout=${1:-300}
    local elapsed=0

    echo "Waiting for Odoo to be ready (this may take a few minutes on first run)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if the database selector page is accessible
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/database/selector" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Odoo is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Odoo readiness check timed out after ${timeout}s"
    return 1
}

# Function to create Odoo database with demo data
create_odoo_database() {
    echo "Creating Odoo database with demo data..."

    # Use curl to create database via Odoo's web interface
    # This creates a database with demo data pre-loaded
    # Note: demo=1 enables demo data, phone field is required (can be empty)
    curl -s -X POST "$ODOO_URL/web/database/create" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "master_pwd=admin&name=$ODOO_DB_NAME&login=$ADMIN_EMAIL&password=$ADMIN_PASS&phone=&lang=en_US&country_code=us&demo=1" \
        -o /tmp/db_create_response.html 2>/dev/null

    # Check if database was created
    sleep 10

    # Verify database exists by checking if we can access the login page
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/login?db=$ODOO_DB_NAME" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Database '$ODOO_DB_NAME' created successfully!"
        return 0
    else
        echo "Database creation may have failed, HTTP code: $HTTP_CODE"
        # Try checking via database selector
        return 1
    fi
}

# Copy docker-compose.yml to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/odoo
cp /workspace/config/docker-compose.yml /home/ga/odoo/
chown -R ga:ga /home/ga/odoo

# Start Odoo containers
echo "Starting Odoo Docker containers..."
cd /home/ga/odoo

# Pull images first (better error handling)
docker-compose pull

# Start containers in detached mode
docker-compose up -d

echo "Containers starting..."
docker-compose ps

# Wait for Odoo to be fully ready
wait_for_odoo 300

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Create demo database
echo ""
echo "Creating Odoo database..."
create_odoo_database

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

// Set homepage to Odoo
user_pref("browser.startup.homepage", "http://localhost:8069/web/login?db=odoo_demo");
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
# Execute SQL query against Odoo PostgreSQL database (via Docker)
docker exec odoo-postgres psql -U odoo -d odoo_demo -t -A -c "$1"
DBQUERYEOF
chmod +x /usr/local/bin/odoo-db-query

# Start Firefox for the ga user
echo "Launching Firefox with Odoo..."
su - ga -c "DISPLAY=:1 firefox '$ODOO_URL/web/login?db=$ODOO_DB_NAME' > /tmp/firefox_odoo.log 2>&1 &"

# Wait for Firefox window
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
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== Odoo Setup Complete ==="
echo ""
echo "Odoo is running at: $ODOO_URL"
echo ""
echo "Login Credentials:"
echo "  Email: $ADMIN_EMAIL"
echo "  Password: $ADMIN_PASS"
echo "  Database: $ODOO_DB_NAME"
echo ""
echo "Database access (via Docker):"
echo "  odoo-db-query \"SELECT COUNT(*) FROM res_partner\""
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/odoo/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/odoo/docker-compose.yml ps"
echo ""
