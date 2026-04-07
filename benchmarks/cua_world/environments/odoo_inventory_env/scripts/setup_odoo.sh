#!/bin/bash
# Odoo Inventory Setup Script (post_start hook)
# Starts Odoo 17 via Docker and launches Firefox
#
# Default credentials: admin / admin
# URL: http://localhost:8069

echo "=== Setting up Odoo Inventory via Docker ==="

# Configuration
ODOO_URL="http://localhost:8069/web/login"
DB_NAME="odoo_inventory"
ADMIN_EMAIL="admin"
ADMIN_PASS="admin"

# Function to wait for Odoo to be ready
wait_for_odoo() {
    local timeout=${1:-300}
    local elapsed=0

    echo "Waiting for Odoo to be ready (this may take a few minutes on first run)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if the web container is responding
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/database/selector" 2>/dev/null)
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

# Function to wait for database to be created
wait_for_database() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for database to be initialized..."

    while [ $elapsed -lt $timeout ]; do
        # Check if we can access the login page (meaning DB is ready)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo "Database ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting for database... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Database readiness check timed out after ${timeout}s"
    return 1
}

# Copy docker-compose.yml and config to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/odoo/addons
cp /workspace/config/docker-compose.yml /home/ga/odoo/
cp /workspace/config/odoo.conf /home/ga/odoo/
touch /home/ga/odoo/addons/__init__.py
chown -R ga:ga /home/ga/odoo

# Start Odoo containers
echo "Starting Odoo Docker containers..."
cd /home/ga/odoo

# Check if we need to clean up old corrupted data
# This handles cases where previous runs left broken database state

# First, check if there are existing volumes
EXISTING_DB_VOL=$(docker volume ls -q 2>/dev/null | grep -E "odoo.*db" || true)
EXISTING_WEB_VOL=$(docker volume ls -q 2>/dev/null | grep -E "odoo.*web" || true)

if [ -n "$EXISTING_DB_VOL" ] || [ -n "$EXISTING_WEB_VOL" ]; then
    echo "Found existing Odoo volumes. Checking database state..."

    # Start containers briefly to check database state
    docker-compose up -d 2>/dev/null || true
    sleep 10

    # Check if database is corrupted (500 error or empty modules)
    DB_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
    echo "Current Odoo HTTP status: $DB_HEALTH"

    if [ "$DB_HEALTH" = "500" ]; then
        echo "Database is corrupted (500 error). Performing full cleanup..."
        docker-compose down -v 2>/dev/null || true
        sleep 5
        echo "Volumes removed. Will create fresh database."
    elif [ "$DB_HEALTH" = "000" ]; then
        echo "Odoo not responding. Proceeding with normal startup."
    fi
else
    echo "No existing Odoo volumes found. Fresh installation."
fi

# Pull images first (better error handling)
docker-compose pull

# Start containers in detached mode
docker-compose up -d

echo "Containers starting..."
docker-compose ps

# Wait for Odoo web service to be ready
wait_for_odoo 300

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Check if Odoo is returning 500 error (broken database state)
echo ""
echo "Checking Odoo health..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
echo "Odoo HTTP status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "500" ]; then
    echo "Odoo returning 500 error - database may be corrupted. Will attempt recovery..."
    FORCE_RECREATE="true"
else
    FORCE_RECREATE="false"
fi

# Check if database needs to be created
echo ""
echo "Checking database status..."

# Create database with demo data using Odoo CLI
DB_EXISTS=$(docker exec odoo-postgres psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null)

if [ "$DB_EXISTS" != "1" ]; then
    echo "Database '$DB_NAME' does not exist. Creating it..."

    # Method 1: Create database directly via PostgreSQL + Odoo initialization
    echo "Creating database via PostgreSQL..."
    docker exec odoo-postgres psql -U odoo -d postgres -c "CREATE DATABASE $DB_NAME OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true

    # Check if database was created
    sleep 3
    DB_EXISTS=$(docker exec odoo-postgres psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null)

    if [ "$DB_EXISTS" = "1" ]; then
        echo "Database created. Initializing Odoo modules with demo data..."
        # Initialize Odoo with base modules and demo data
        # The -i flag installs modules, --load-language ensures translations
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "$DB_NAME" -i base,stock,sale_management,purchase --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -30 || {
            echo "First init attempt completed (may have warnings)"
        }

        # Wait for initialization
        sleep 10

        # Verify modules are installed
        MODULES_OK=$(docker exec odoo-postgres psql -U odoo -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null || echo "0")

        if [ "$MODULES_OK" -ge "1" ]; then
            echo "Odoo modules installed successfully!"

            # Set admin credentials explicitly
            echo "Setting admin credentials..."
            docker exec odoo-postgres psql -U odoo -d "$DB_NAME" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true

            # Load demo data for stock module specifically
            echo "Loading demo data for inventory..."
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "$DB_NAME" -u stock --stop-after-init 2>&1 | tail -10 || true

            echo "Restarting Odoo web server..."
            docker-compose restart web
            sleep 15
            wait_for_odoo 120

            echo "Database '$DB_NAME' initialized successfully!"
        else
            echo "WARNING: Module installation may have failed. Checking status..."
        fi
    else
        echo "WARNING: PostgreSQL database creation failed."
    fi

    # Final check - if database still doesn't exist or isn't initialized
    DB_EXISTS=$(docker exec odoo-postgres psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null)
    MODULES_OK=$(docker exec odoo-postgres psql -U odoo -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null 2>/dev/null || echo "0")

    if [ "$DB_EXISTS" != "1" ] || [ "$MODULES_OK" -lt "1" ]; then
        echo ""
        echo "NOTE: Automated database creation incomplete."
        echo "The agent may see a database creation form. To create the database:"
        echo "  - Database Name: $DB_NAME"
        echo "  - Email: $ADMIN_EMAIL"
        echo "  - Password: $ADMIN_PASS"
        echo "  - Check 'Demo Data' checkbox"
        echo ""
    fi
else
    echo "Database '$DB_NAME' already exists"

    # Check if the database has any tables (sanity check)
    TABLE_COUNT=$(docker exec odoo-postgres psql -U odoo -d $DB_NAME -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo "0")
    echo "Database has $TABLE_COUNT tables"

    # If database exists but is empty/broken, or Odoo returns 500 error, drop and recreate it
    if [ "$TABLE_COUNT" -lt "10" ] || [ "$FORCE_RECREATE" = "true" ]; then
        if [ "$FORCE_RECREATE" = "true" ]; then
            echo "Forcing database recreation due to Odoo 500 error..."
        fi
        echo "Database appears empty or corrupt. Dropping and recreating..."
        docker exec odoo-postgres psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME" 2>/dev/null || true
        sleep 2
        docker exec odoo-postgres psql -U odoo -d postgres -c "CREATE DATABASE $DB_NAME OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2

        echo "Initializing Odoo modules with demo data..."
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "$DB_NAME" -i base,stock,sale_management,purchase --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -30 || {
            echo "Module initialization completed (may have warnings)"
        }

        # Set admin credentials
        echo "Setting admin credentials..."
        docker exec odoo-postgres psql -U odoo -d "$DB_NAME" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true

        # Restart Odoo
        echo "Restarting Odoo..."
        docker-compose restart web
        sleep 15
        wait_for_odoo 120
    fi

    # Check if the database has any modules installed (base is essential)
    BASE_INSTALLED=$(docker exec odoo-postgres psql -U odoo -d $DB_NAME -tAc "SELECT 1 FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null || echo "")

    if [ "$BASE_INSTALLED" != "1" ]; then
        echo "Database exists but has no modules installed. Initializing Odoo..."
        # The database is empty - need full initialization
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "$DB_NAME" -i base,stock,sale_management,purchase --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -30 || {
            echo "Module initialization completed (may have warnings)"
        }

        # Set admin credentials
        echo "Setting admin credentials..."
        docker exec odoo-postgres psql -U odoo -d "$DB_NAME" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true

        # Restart Odoo
        echo "Restarting Odoo..."
        docker-compose restart web
        sleep 15
        wait_for_odoo 120
    else
        # Base is installed, check for stock module
        STOCK_INSTALLED=$(docker exec odoo-postgres psql -U odoo -d $DB_NAME -tAc "SELECT 1 FROM ir_module_module WHERE name='stock' AND state='installed'" 2>/dev/null)

        if [ "$STOCK_INSTALLED" != "1" ]; then
            echo "Installing Inventory module..."
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d $DB_NAME -i stock --stop-after-init 2>&1 | tail -10 || true
            echo "Restarting Odoo..."
            docker-compose restart web
            sleep 15
            wait_for_odoo 120
        else
            echo "All required modules already installed."
        fi
    fi
fi

# If database exists and has required modules, we can skip installation
# Module installation is handled in the database existence check above

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
user_pref("browser.startup.homepage", "http://localhost:8069/web/login");
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
Name=Odoo Inventory
Comment=Odoo ERP - Inventory Management
Exec=firefox http://localhost:8069/web/login
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Inventory;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Odoo.desktop
chmod +x /home/ga/Desktop/Odoo.desktop

# Create utility script for database queries
cat > /usr/local/bin/odoo-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Odoo database (via Docker)
docker exec odoo-postgres psql -U odoo -d odoo_inventory -c "$1"
DBQUERYEOF
chmod +x /usr/local/bin/odoo-db-query

# Create utility script for Odoo shell
cat > /usr/local/bin/odoo-shell << 'SHELLEOF'
#!/bin/bash
# Run Odoo shell command (via Docker)
docker exec -it odoo-web odoo shell -d odoo_inventory "$@"
SHELLEOF
chmod +x /usr/local/bin/odoo-shell

# Start Firefox for the ga user
echo "Launching Firefox with Odoo..."
su - ga -c "DISPLAY=:1 firefox '$ODOO_URL' > /tmp/firefox_odoo.log 2>&1 &"

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
echo "=== Odoo Inventory Setup Complete ==="
echo ""
echo "Odoo is running at: http://localhost:8069/"
echo ""
echo "Login Credentials:"
echo "  Email/Username: ${ADMIN_EMAIL}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "Database: $DB_NAME (with demo data)"
echo ""
echo "Installed Modules:"
echo "  - Inventory (stock)"
echo "  - Sales (sale_management)"
echo "  - Purchase (purchase)"
echo ""
echo "Database access (via Docker):"
echo "  odoo-db-query \"SELECT count(*) FROM product_template\""
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/odoo/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/odoo/docker-compose.yml ps"
echo ""

# Flush all data to disk — critical for QEMU checkpoint consistency
echo "Flushing data to disk for checkpoint consistency..."
# Force PostgreSQL to checkpoint (flush WAL to disk)
PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'odoo.*(db|postgres)' | head -1)
if [ -n "$PG_CONTAINER" ]; then
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CHECKPOINT" 2>/dev/null || true
    echo "PostgreSQL checkpoint issued on $PG_CONTAINER"
fi
sync
echo "Disk sync complete."
