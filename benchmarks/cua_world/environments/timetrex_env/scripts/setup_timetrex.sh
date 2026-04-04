#!/bin/bash
# TimeTrex Setup Script (post_start hook)
# Builds and starts TimeTrex via Docker, generates demo data, and launches Firefox
#
# Demo credentials: demoadmin1 / demo (after demo data generation)
# Admin credentials: admin / admin (initial setup)

echo "=== Setting up TimeTrex via Docker ==="

# Configuration
TIMETREX_URL="http://localhost/interface/Login.php"
ADMIN_USER="demoadmin1"
ADMIN_PASS="demo"

# Function to wait for TimeTrex to be ready
wait_for_timetrex() {
    local timeout=${1:-300}
    local elapsed=0

    echo "Waiting for TimeTrex to be ready (this may take several minutes on first run)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if the login page returns HTTP 200
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TIMETREX_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo "TimeTrex is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: TimeTrex readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for PostgreSQL to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
            echo "PostgreSQL is ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    echo "WARNING: PostgreSQL readiness check timed out after ${timeout}s"
    return 1
}

# Copy Docker files to working directory
echo "Setting up Docker configuration..."
mkdir -p /home/ga/timetrex
cp /workspace/config/docker-compose.yml /home/ga/timetrex/
cp /workspace/config/Dockerfile.timetrex /home/ga/timetrex/
cp /workspace/config/timetrex.ini.php /home/ga/timetrex/
chown -R ga:ga /home/ga/timetrex

# Create robust startup script that ensures containers are running
echo "Creating TimeTrex startup script..."
cat > /usr/local/bin/timetrex-ensure-running << 'STARTUPEOF'
#!/bin/bash
# TimeTrex Startup Script - Ensures Docker containers are running
# This script is called on boot, checkpoint restore, and before each task

LOG_FILE="/var/log/timetrex-startup.log"
TIMETREX_DIR="/home/ga/timetrex"
MAX_RETRIES=10
RETRY_DELAY=5

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "=== TimeTrex Startup Script Started ==="

# Step 1: Ensure Docker daemon is running
log "Step 1: Checking Docker daemon..."
for i in $(seq 1 $MAX_RETRIES); do
    if docker info >/dev/null 2>&1; then
        log "Docker daemon is running"
        break
    fi

    log "Docker not responding, attempting to start (attempt $i/$MAX_RETRIES)..."
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep $RETRY_DELAY

    if [ $i -eq $MAX_RETRIES ]; then
        log "FATAL: Docker daemon failed to start after $MAX_RETRIES attempts"
        exit 1
    fi
done

# Step 2: Check if containers exist and are running
log "Step 2: Checking container status..."
cd "$TIMETREX_DIR" || {
    log "FATAL: Cannot cd to $TIMETREX_DIR"
    exit 1
}

PG_RUNNING=$(docker ps -q -f name=timetrex-postgres -f status=running 2>/dev/null)
APP_RUNNING=$(docker ps -q -f name=timetrex-app -f status=running 2>/dev/null)

if [ -z "$PG_RUNNING" ] || [ -z "$APP_RUNNING" ]; then
    log "Containers not running. Current status:"
    docker ps -a --filter name=timetrex 2>&1 | tee -a "$LOG_FILE"

    # Stop any existing containers
    log "Stopping existing containers..."
    docker-compose down --remove-orphans 2>&1 | tee -a "$LOG_FILE" || true
    docker rm -f timetrex-postgres timetrex-app 2>/dev/null || true
    sleep 2

    # Start fresh
    log "Starting containers with docker-compose..."
    docker-compose up -d 2>&1 | tee -a "$LOG_FILE"

    # Wait for containers to be running
    for i in $(seq 1 60); do
        PG_RUNNING=$(docker ps -q -f name=timetrex-postgres -f status=running 2>/dev/null)
        APP_RUNNING=$(docker ps -q -f name=timetrex-app -f status=running 2>/dev/null)
        if [ -n "$PG_RUNNING" ] && [ -n "$APP_RUNNING" ]; then
            log "Containers started after ${i}s"
            break
        fi
        sleep 1
    done
fi

# Step 3: Wait for PostgreSQL to accept connections
log "Step 3: Waiting for PostgreSQL..."
for i in $(seq 1 120); do
    if docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
        log "PostgreSQL ready after ${i}s"
        break
    fi
    [ $((i % 10)) -eq 0 ] && log "Still waiting for PostgreSQL... ${i}s"
    sleep 1

    if [ $i -eq 120 ]; then
        log "ERROR: PostgreSQL not ready after 120s"
        docker logs timetrex-postgres 2>&1 | tail -30 | tee -a "$LOG_FILE"
    fi
done

# Step 4: Wait for TimeTrex web interface
log "Step 4: Waiting for TimeTrex web interface..."
for i in $(seq 1 180); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/interface/Login.php 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        log "TimeTrex web ready after ${i}s (HTTP $HTTP_CODE)"
        break
    fi
    [ $((i % 15)) -eq 0 ] && log "Still waiting for web... ${i}s (HTTP $HTTP_CODE)"
    sleep 1

    if [ $i -eq 180 ]; then
        log "ERROR: TimeTrex web not accessible after 180s"
        docker logs timetrex-app 2>&1 | tail -50 | tee -a "$LOG_FILE"
    fi
done

# Step 5: Verify demo data exists
log "Step 5: Verifying demo data..."
USER_COUNT=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users" 2>/dev/null | tr -d ' ')

if [ -z "$USER_COUNT" ] || [ "$USER_COUNT" -lt 5 ]; then
    log "Insufficient demo data (user count: ${USER_COUNT:-0}), regenerating..."
    docker exec timetrex-app php /var/www/html/timetrex/tools/create_demo_data.php 2>&1 | tee -a "$LOG_FILE" || true
    sleep 5
    USER_COUNT=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users" 2>/dev/null | tr -d ' ')
fi
log "Database has $USER_COUNT users"

# Step 6: Verify critical employees exist
log "Step 6: Verifying critical employees..."
JOHN_EXISTS=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users WHERE first_name='John' AND last_name='Doe'" 2>/dev/null | tr -d ' ')
JANE_EXISTS=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users WHERE first_name='Jane' AND last_name='Doe'" 2>/dev/null | tr -d ' ')
HEATHER_EXISTS=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users WHERE first_name='Heather' AND last_name='Grant'" 2>/dev/null | tr -d ' ')

log "Employee check: John Doe=$JOHN_EXISTS, Jane Doe=$JANE_EXISTS, Heather Grant=$HEATHER_EXISTS"

# Final verification
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/interface/Login.php 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    log "=== TimeTrex Startup Complete - SUCCESS ==="
    exit 0
else
    log "=== TimeTrex Startup Complete - FAILED (HTTP $HTTP_CODE) ==="
    exit 1
fi
STARTUPEOF
chmod +x /usr/local/bin/timetrex-ensure-running

# Create systemd service that runs the startup script
echo "Creating systemd service for TimeTrex..."
cat > /etc/systemd/system/timetrex-docker.service << 'SYSTEMDEOF'
[Unit]
Description=TimeTrex Docker Containers
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/timetrex-ensure-running
ExecStop=/usr/bin/docker-compose -f /home/ga/timetrex/docker-compose.yml down
TimeoutStartSec=600
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

# Create timer to check/restart containers periodically (every 30 seconds)
cat > /etc/systemd/system/timetrex-health.service << 'HEALTHEOF'
[Unit]
Description=TimeTrex Health Check
After=timetrex-docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/timetrex-ensure-running
StandardOutput=journal
StandardError=journal
HEALTHEOF

cat > /etc/systemd/system/timetrex-health.timer << 'TIMEREOF'
[Unit]
Description=TimeTrex Health Check Timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=10s

[Install]
WantedBy=timers.target
TIMEREOF

# Create rc.local fallback for checkpoint restore
cat > /etc/rc.local << 'RCLOCALEOF'
#!/bin/bash
# Fallback startup for TimeTrex on checkpoint restore
sleep 5
/usr/local/bin/timetrex-ensure-running &
exit 0
RCLOCALEOF
chmod +x /etc/rc.local

# Enable all services
systemctl daemon-reload
systemctl enable timetrex-docker.service
systemctl enable timetrex-health.timer

# Build and start TimeTrex containers
echo "Building and starting TimeTrex Docker containers..."
cd /home/ga/timetrex

# Build the TimeTrex image
docker-compose build --no-cache || {
    echo "Docker build failed. Checking logs..."
    docker-compose logs
    exit 1
}

# Start containers in detached mode
docker-compose up -d

echo "Containers starting..."
docker-compose ps

# Wait for PostgreSQL first
wait_for_postgres 120

# Wait for TimeTrex to be fully ready (including web interface)
# Give extra time for first-time setup
wait_for_timetrex 300

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Check if this is first run and run installer if needed
echo ""
echo "Checking TimeTrex installation status..."

# Check if the database has been initialized
DB_INITIALIZED=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$DB_INITIALIZED" = "0" ] || [ -z "$DB_INITIALIZED" ]; then
    echo "Database not initialized. Running TimeTrex installer..."

    # Run the CLI installer to initialize the database
    docker exec timetrex-app php /var/www/html/timetrex/tools/install/install.php --installer_db=postgres --installer_db_host=postgres --installer_db_user=timetrex --installer_db_password=timetrex --installer_db_database=timetrex --installer_email=admin@example.com --installer_password=admin --installer_company_name="Demo Company" --installer_first_name=Admin --installer_last_name=User || {
        echo "CLI installer failed or not available, database may auto-initialize"
    }
fi

# Generate demo data
echo ""
echo "Generating demo data..."

# Create demo data generation script
cat > /tmp/generate_demo_data.php << 'DEMOSCRIPT'
<?php
// TimeTrex Demo Data Generator
// This creates realistic sample employees, schedules, and time entries

error_reporting(E_ALL);
ini_set('display_errors', 1);

// Include TimeTrex environment
$config_path = '/var/www/html/timetrex/timetrex.ini.php';
if (!file_exists($config_path)) {
    echo "Config file not found at: $config_path\n";
    exit(1);
}

require_once('/var/www/html/timetrex/classes/DemoData.class.php');

try {
    // Initialize demo data generator
    $demo = new DemoData();
    $demo->UserNamePostFix = 1;

    echo "Starting demo data generation...\n";
    $demo->createDemoData();
    echo "Demo data generation complete!\n";
    echo "Login with: demoadmin1 / demo\n";
} catch (Exception $e) {
    echo "Error generating demo data: " . $e->getMessage() . "\n";
    exit(1);
}
?>
DEMOSCRIPT

# Copy script to container and run
docker cp /tmp/generate_demo_data.php timetrex-app:/tmp/generate_demo_data.php
docker exec timetrex-app php /tmp/generate_demo_data.php 2>&1 || {
    echo "Demo data generation may have encountered issues. Continuing with setup..."
}
rm -f /tmp/generate_demo_data.php

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

// Set homepage to TimeTrex
user_pref("browser.startup.homepage", "http://localhost/interface/Login.php");
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
cat > /home/ga/Desktop/TimeTrex.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=TimeTrex
Comment=Workforce Management
Exec=firefox http://localhost/interface/Login.php
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Business;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/TimeTrex.desktop
chmod +x /home/ga/Desktop/TimeTrex.desktop

# Create utility script for database queries
cat > /usr/local/bin/timetrex-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against TimeTrex database (via Docker)
docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1"
DBQUERYEOF
chmod +x /usr/local/bin/timetrex-db-query

# Create utility script for psql interactive
cat > /usr/local/bin/timetrex-psql << 'PSQLEOF'
#!/bin/bash
# Interactive psql session for TimeTrex database
docker exec -it timetrex-postgres psql -U timetrex -d timetrex
PSQLEOF
chmod +x /usr/local/bin/timetrex-psql

# Start Firefox for the ga user
echo "Launching Firefox with TimeTrex..."
su - ga -c "DISPLAY=:1 firefox '$TIMETREX_URL' > /tmp/firefox_timetrex.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|timetrex"; then
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
echo "=== TimeTrex Setup Complete ==="
echo ""
echo "TimeTrex is running at: http://localhost/"
echo ""
echo "Login Credentials (Demo Mode):"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "Database access (via Docker):"
echo "  timetrex-db-query \"SELECT COUNT(*) FROM users\""
echo "  timetrex-psql  (interactive)"
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/timetrex/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/timetrex/docker-compose.yml ps"
echo ""
