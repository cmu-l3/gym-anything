#!/bin/bash
# Booked Scheduler Setup Script (post_start hook)
# Starts Booked via Docker, runs DB install, loads realistic data, launches Firefox
#
# Default credentials: admin / password

echo "=== Setting up Booked Scheduler via Docker ==="

BOOKED_URL="http://localhost/Web/dashboard.php"
BOOKED_LOGIN_URL="http://localhost/Web/index.php"
ADMIN_USER="admin"
ADMIN_PASS="password"

# -------------------------------------------------------------------
# Phase 1: Copy config and start Docker Compose
# -------------------------------------------------------------------
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/booked
cp /workspace/config/docker-compose.yml /home/ga/booked/
cp /workspace/config/site.conf /home/ga/booked/
chown -R ga:ga /home/ga/booked

cd /home/ga/booked

# Docker Hub auth
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# Start containers
echo "Starting Booked Scheduler Docker containers..."
docker-compose pull
docker-compose up -d

echo "Containers starting..."
docker-compose ps

# -------------------------------------------------------------------
# Phase 2: Wait for MySQL readiness
# -------------------------------------------------------------------
echo "Waiting for MySQL to be ready..."
for i in $(seq 1 60); do
    if docker exec booked-db mysqladmin ping -h localhost -uroot -proot >/dev/null 2>&1; then
        echo "MySQL ready after $((i * 2))s"
        break
    fi
    sleep 2
done

# Verify database exists
docker exec booked-db mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS bookedscheduler" 2>/dev/null || true
docker exec booked-db mysql -uroot -proot -e "GRANT ALL PRIVILEGES ON bookedscheduler.* TO 'booked_user'@'%'" 2>/dev/null || true
docker exec booked-db mysql -uroot -proot -e "FLUSH PRIVILEGES" 2>/dev/null || true

# -------------------------------------------------------------------
# Phase 3: Wait for Nginx/PHP readiness
# -------------------------------------------------------------------
echo "Waiting for web server to be ready..."
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/Web/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "Web server ready after $((i * 3))s (HTTP $HTTP_CODE)"
        break
    fi
    sleep 3
    echo "  Waiting... $((i * 3))s (HTTP $HTTP_CODE)"
done

# -------------------------------------------------------------------
# Phase 4: Install Booked Scheduler database schema
# -------------------------------------------------------------------
echo "Installing Booked Scheduler database schema..."

# Check if schema already exists (idempotent)
TABLE_COUNT=$(docker exec booked-db mysql -ubooked_user -ppassword bookedscheduler -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='bookedscheduler'" 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -lt "5" ]; then
    echo "Running schema creation..."

    # Extract and run create-schema.sql from the booked container
    docker exec booked-app cat /var/www/booked/database_schema/create-schema.sql > /tmp/create-schema.sql 2>/dev/null
    if [ -s /tmp/create-schema.sql ]; then
        docker cp /tmp/create-schema.sql booked-db:/tmp/create-schema.sql
        docker exec booked-db mysql -ubooked_user -ppassword bookedscheduler -e "source /tmp/create-schema.sql" 2>&1 | tail -5
        echo "Schema created."
    else
        echo "WARNING: Could not extract schema SQL. Trying web installer..."
        curl -s -X POST "http://localhost/Web/install/configure.php" \
            -d "install_password=install123&run_install=1" 2>/dev/null || true
    fi

    # Run create-data.sql (essential lookup data: reservation types, statuses, time blocks, schedules)
    echo "Loading essential lookup data..."
    docker exec booked-app cat /var/www/booked/database_schema/create-data.sql > /tmp/create-data.sql 2>/dev/null
    if [ -s /tmp/create-data.sql ]; then
        docker cp /tmp/create-data.sql booked-db:/tmp/create-data.sql
        docker exec booked-db mysql --force -ubooked_user -ppassword bookedscheduler -e "source /tmp/create-data.sql" 2>&1 | tail -5
        echo "Lookup data loaded."
    fi

    # Run sample data (users, resources, accessories)
    echo "Loading sample data..."
    docker exec booked-app cat /var/www/booked/database_schema/sample-data-utf8.sql > /tmp/sample-data.sql 2>/dev/null
    if [ -s /tmp/sample-data.sql ]; then
        docker cp /tmp/sample-data.sql booked-db:/tmp/sample-data.sql
        docker exec booked-db mysql --force -ubooked_user -ppassword bookedscheduler -e "source /tmp/sample-data.sql" 2>&1 | tail -5
        echo "Sample data loaded."
    fi

    echo "Database setup complete."
else
    echo "Schema already exists ($TABLE_COUNT tables). Skipping installation."
fi

# Clean up temp files
rm -f /tmp/create-schema.sql /tmp/sample-data.sql

# -------------------------------------------------------------------
# Phase 5: Load realistic data
# -------------------------------------------------------------------
echo "Loading realistic data..."
if [ -f /workspace/data/seed_realistic_data.sql ]; then
    docker cp /workspace/data/seed_realistic_data.sql booked-db:/tmp/seed_realistic_data.sql
    docker exec booked-db mysql --force -ubooked_user -ppassword bookedscheduler -e "source /tmp/seed_realistic_data.sql" 2>&1 | grep -v "Duplicate entry" | tail -10
    docker exec booked-db rm -f /tmp/seed_realistic_data.sql
    echo "Realistic data loaded."
else
    echo "WARNING: seed_realistic_data.sql not found"
fi

# Verify data load
echo ""
echo "Data verification:"
RESOURCE_COUNT=$(docker exec booked-db mysql -ubooked_user -ppassword bookedscheduler -N -e "SELECT COUNT(*) FROM resources" 2>/dev/null)
USER_COUNT=$(docker exec booked-db mysql -ubooked_user -ppassword bookedscheduler -N -e "SELECT COUNT(*) FROM users" 2>/dev/null)
echo "  Resources: $RESOURCE_COUNT"
echo "  Users: $USER_COUNT"

# -------------------------------------------------------------------
# Phase 6: Create database query helper
# -------------------------------------------------------------------
cat > /usr/local/bin/booked-db-query << 'DBQUERYEOF'
#!/bin/bash
docker exec booked-db mysql -ubooked_user -ppassword bookedscheduler -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/booked-db-query

# -------------------------------------------------------------------
# Phase 7: Configure Firefox profile
# -------------------------------------------------------------------
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

// Set homepage to Booked Scheduler login
user_pref("browser.startup.homepage", "http://localhost/Web/index.php");
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
cat > /home/ga/Desktop/BookedScheduler.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Booked Scheduler
Comment=Resource Reservation System
Exec=firefox http://localhost/Web/index.php
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;ProjectManagement;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/BookedScheduler.desktop
chmod +x /home/ga/Desktop/BookedScheduler.desktop

# -------------------------------------------------------------------
# Phase 8: Launch Firefox
# -------------------------------------------------------------------
echo "Launching Firefox with Booked Scheduler..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox '$BOOKED_LOGIN_URL' > /tmp/firefox_booked.log 2>&1 &"

# Wait for Firefox window
FIREFOX_STARTED=false
for i in $(seq 1 40); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|booked"; then
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
echo "=== Booked Scheduler Setup Complete ==="
echo ""
echo "Booked Scheduler is running at: http://localhost/Web/"
echo ""
echo "Login Credentials:"
echo "  Admin:  ${ADMIN_USER} / ${ADMIN_PASS}"
echo "  User:   user / password"
echo ""
echo "Database access:"
echo "  booked-db-query \"SELECT COUNT(*) FROM resources\""
echo ""
