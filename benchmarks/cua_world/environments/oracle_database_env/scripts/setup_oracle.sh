#!/bin/bash
# Oracle Database XE Setup Script (post_start hook)
# Starts Oracle Database XE via Docker, loads HR sample schema, and launches SQL Developer

# Exit immediately if any command fails (with some exceptions handled explicitly)
set -e

# Trap to log when script exits
trap 'echo "Setup script exiting with code $?"' EXIT

echo "=== Setting up Oracle Database XE ==="

# Configuration
ORACLE_PWD="OraclePassword123"
ORACLE_CONTAINER="oracle-xe"
ORACLE_PORT=1521
EM_PORT=5500
HR_USER="hr"
HR_PWD="hr123"

# Function to wait for Oracle to be ready
wait_for_oracle() {
    local timeout=${1:-300}
    local elapsed=0
    local min_wait=90  # Minimum wait time before checking (Oracle XE needs 60-120s to start)

    echo "Waiting for Oracle Database to be ready (this may take 2-3 minutes on first run)..."

    # Always wait at least min_wait seconds - Oracle XE needs significant startup time
    echo "  Initial wait for Oracle startup (${min_wait}s)..."
    sleep $min_wait
    elapsed=$min_wait

    while [ $elapsed -lt $timeout ]; do
        # Check if container is healthy first
        local container_status=$(sudo docker inspect --format='{{.State.Status}}' $ORACLE_CONTAINER 2>/dev/null)
        if [ "$container_status" != "running" ]; then
            echo "  Container not running yet (status: $container_status)... ${elapsed}s"
            sleep 10
            elapsed=$((elapsed + 10))
            continue
        fi

        # Check if Oracle listener is up by testing XEPDB1 connection (the PDB we'll use)
        # Use SET commands to ensure clean output and look for "1" anywhere in result
        echo "  Testing Oracle XEPDB1 connection at ${elapsed}s..."
        local test_output=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s system/${ORACLE_PWD}@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 100
SELECT 1 FROM DUAL;
EXIT;
SQLEOF" 2>&1)

        # Check for ORA- errors (connection failures)
        if echo "$test_output" | grep -q "ORA-"; then
            local ora_error=$(echo "$test_output" | grep "ORA-" | head -1)
            echo "  Oracle not ready: $ora_error... ${elapsed}s"
            sleep 10
            elapsed=$((elapsed + 10))
            continue
        fi

        # Check if we got "1" in the output (successful query)
        if echo "$test_output" | grep -qE '^\s*1\s*$'; then
            echo "  Oracle listener is accepting connections after ${elapsed}s"

            # Double-check with a second query to ensure stability
            echo "  Verifying Oracle stability..."
            sleep 5
            local verify_output=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s system/${ORACLE_PWD}@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM dba_users;
EXIT;
SQLEOF" 2>&1)

            # Check for numeric result (user count)
            local user_count=$(echo "$verify_output" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')
            if [ -n "$user_count" ] && [ "$user_count" -gt 0 ] 2>/dev/null; then
                echo "Oracle Database XEPDB1 verified ready after ${elapsed}s (found $user_count users)"
                return 0
            else
                echo "  Verification query failed, retrying..."
            fi
        fi

        echo "  Waiting for Oracle... ${elapsed}s"
        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo "ERROR: Oracle readiness check timed out after ${timeout}s"
    echo "Last test output: $test_output"
    return 1
}

# Stop any existing Oracle container
echo "Stopping any existing Oracle container..."
sudo docker stop $ORACLE_CONTAINER 2>/dev/null || true
sudo docker rm $ORACLE_CONTAINER 2>/dev/null || true

# Start Oracle XE container
echo "Starting Oracle Database XE container..."
sudo docker run -d \
    --name $ORACLE_CONTAINER \
    -p ${ORACLE_PORT}:1521 \
    -p ${EM_PORT}:5500 \
    -e ORACLE_PASSWORD=${ORACLE_PWD} \
    -e ORACLE_CHARACTERSET=AL32UTF8 \
    -v oracle_data:/opt/oracle/oradata \
    gvenzl/oracle-xe:21-slim

echo "Container starting..."
sudo docker ps | grep $ORACLE_CONTAINER

# Wait for Oracle to be fully ready - FAIL if not ready
if ! wait_for_oracle 300; then
    echo ""
    echo "=============================================="
    echo "CRITICAL ERROR: Oracle Database failed to start!"
    echo "=============================================="
    echo ""
    echo "The environment cannot proceed without a working database."
    echo "Check Docker logs: sudo docker logs oracle-xe"
    exit 1
fi

# Show container status
echo ""
echo "Container status:"
sudo docker ps | grep $ORACLE_CONTAINER

# Load HR sample schema from Oracle's official GitHub repository
echo ""
echo "Loading HR sample schema from Oracle's official repository..."

# Download HR schema scripts
HR_SCRIPTS_DIR="/tmp/hr_schema"
mkdir -p $HR_SCRIPTS_DIR
cd $HR_SCRIPTS_DIR

# Download from Oracle's official db-sample-schemas repository
echo "Downloading HR schema from GitHub..."
wget -q https://raw.githubusercontent.com/oracle-samples/db-sample-schemas/main/human_resources/hr_main.sql -O hr_main.sql || true
wget -q https://raw.githubusercontent.com/oracle-samples/db-sample-schemas/main/human_resources/hr_cre.sql -O hr_cre.sql || true
wget -q https://raw.githubusercontent.com/oracle-samples/db-sample-schemas/main/human_resources/hr_popul.sql -O hr_popul.sql || true

# If GitHub download fails, use embedded minimal HR schema
if [ ! -s hr_cre.sql ]; then
    echo "Using embedded HR schema..."
    cp /workspace/data/hr_schema.sql $HR_SCRIPTS_DIR/ 2>/dev/null || true
fi

# Create HR user and grant privileges with retry logic
echo "Creating HR user and schema..."
HR_USER_CREATED=false
for attempt in {1..3}; do
    echo "  Attempt $attempt to create HR user..."
    HR_CREATE_OUTPUT=$(sudo docker exec -i $ORACLE_CONTAINER sqlplus -s system/${ORACLE_PWD}@localhost:1521/XEPDB1 << 'SQLEOF'
SET HEADING OFF
SET FEEDBACK ON
-- Drop existing HR user if exists (clean slate)
BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr CASCADE';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

-- Create HR user
CREATE USER hr IDENTIFIED BY hr123
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

-- Grant privileges
GRANT CREATE SESSION TO hr;
GRANT CREATE TABLE TO hr;
GRANT CREATE VIEW TO hr;
GRANT CREATE SEQUENCE TO hr;
GRANT CREATE PROCEDURE TO hr;
GRANT CREATE TRIGGER TO hr;
GRANT CONNECT, RESOURCE TO hr;

-- Verify user was created
SELECT 'HR_USER_EXISTS' FROM dba_users WHERE username = 'HR';

EXIT;
SQLEOF
    )

    # Check for ORA- errors
    if echo "$HR_CREATE_OUTPUT" | grep -q "ORA-"; then
        echo "  Error creating HR user: $(echo "$HR_CREATE_OUTPUT" | grep "ORA-" | head -1)"
        sleep 10
        continue
    fi

    # Check if user was created
    if echo "$HR_CREATE_OUTPUT" | grep -q "HR_USER_EXISTS"; then
        echo "  HR user created successfully"
        HR_USER_CREATED=true
        break
    fi

    sleep 5
done

if [ "$HR_USER_CREATED" != "true" ]; then
    echo ""
    echo "=============================================="
    echo "CRITICAL ERROR: Failed to create HR user!"
    echo "=============================================="
    echo ""
    echo "Output: $HR_CREATE_OUTPUT"
    echo ""
    echo "The environment cannot proceed without the HR schema user."
    exit 1
fi

# Load HR schema data (use embedded SQL if available) with retry logic
if [ -f /workspace/data/hr_schema.sql ]; then
    echo "Loading HR schema data..."
    SCHEMA_LOADED=false
    for attempt in {1..3}; do
        echo "  Attempt $attempt to load HR schema..."

        # Use piped input to avoid file permission issues in container
        LOAD_OUTPUT=$(sudo docker exec -i $ORACLE_CONTAINER sqlplus -s hr/hr123@localhost:1521/XEPDB1 < /workspace/data/hr_schema.sql 2>&1)

        # Check for ORA- errors during load
        if echo "$LOAD_OUTPUT" | grep -q "ORA-01017"; then
            echo "  Authentication failed - HR user may not be ready yet"
            sleep 10
            continue
        fi

        if echo "$LOAD_OUTPUT" | grep -q "ORA-12541"; then
            echo "  TNS listener not ready"
            sleep 10
            continue
        fi

        # Verify schema loaded successfully
        echo "  Verifying HR schema loaded..."
        VERIFY_OUTPUT=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM employees;
EXIT;
SQLEOF" 2>&1)

        # Extract employee count
        SCHEMA_COUNT=$(echo "$VERIFY_OUTPUT" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')

        if [ -n "$SCHEMA_COUNT" ] && [ "$SCHEMA_COUNT" -gt 0 ] 2>/dev/null; then
            echo "  HR schema loaded successfully with $SCHEMA_COUNT employees"
            SCHEMA_LOADED=true
            break
        else
            echo "  Schema verification failed, retrying..."
            sleep 5
        fi
    done

    if [ "$SCHEMA_LOADED" != "true" ]; then
        echo ""
        echo "=============================================="
        echo "CRITICAL ERROR: Failed to load HR schema!"
        echo "=============================================="
        echo ""
        echo "Last verification output: $VERIFY_OUTPUT"
        echo ""
        echo "The environment cannot proceed without the HR schema data."
        exit 1
    fi
fi

# Final verification of HR schema - MUST have 100+ employees
echo ""
echo "Final verification of HR schema..."
EMPLOYEE_COUNT=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM employees;
EXIT;
SQLEOF" 2>&1 | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')

if [ -z "$EMPLOYEE_COUNT" ] || [ "$EMPLOYEE_COUNT" -lt 100 ] 2>/dev/null; then
    echo ""
    echo "=============================================="
    echo "CRITICAL ERROR: HR schema verification failed!"
    echo "=============================================="
    echo ""
    echo "Expected 100+ employees, found: ${EMPLOYEE_COUNT:-0}"
    echo ""
    echo "The environment cannot proceed without valid HR data."
    exit 1
fi

echo "HR schema verified: $EMPLOYEE_COUNT employees"

# Set up Firefox profile for SQL Developer web access
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

# Create user.js to configure Firefox
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Oracle EM Express
user_pref("browser.startup.homepage", "https://localhost:5500/em/");
user_pref("browser.startup.page", 1);

// Disable update checks and popups
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);

// Accept self-signed certificates for EM Express
user_pref("security.enterprise_roots.enabled", true);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcuts
mkdir -p /home/ga/Desktop

# SQL Developer shortcut
if [ -f /opt/sqldeveloper/sqldeveloper.sh ]; then
    cat > /home/ga/Desktop/SQLDeveloper.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=SQL Developer
Comment=Oracle SQL Developer IDE
Exec=/usr/local/bin/sqldeveloper
Icon=/opt/sqldeveloper/icon.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Database;
DESKTOPEOF
    chown ga:ga /home/ga/Desktop/SQLDeveloper.desktop
    chmod +x /home/ga/Desktop/SQLDeveloper.desktop
    # Mark desktop file as trusted (GNOME requirement)
    su - ga -c "dbus-launch gio set /home/ga/Desktop/SQLDeveloper.desktop metadata::trusted true" 2>/dev/null || true
fi

# DBeaver shortcut (alternative)
cat > /home/ga/Desktop/DBeaver.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=DBeaver
Comment=Universal Database Tool
Exec=dbeaver-ce
Icon=dbeaver
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Database;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/DBeaver.desktop
chmod +x /home/ga/Desktop/DBeaver.desktop
# Mark desktop file as trusted (GNOME requirement)
su - ga -c "dbus-launch gio set /home/ga/Desktop/DBeaver.desktop metadata::trusted true" 2>/dev/null || true

# Oracle EM Express shortcut
cat > /home/ga/Desktop/OracleEM.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Oracle EM Express
Comment=Oracle Enterprise Manager Express
Exec=firefox https://localhost:5500/em/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Database;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OracleEM.desktop
chmod +x /home/ga/Desktop/OracleEM.desktop
# Mark desktop file as trusted (GNOME requirement)
su - ga -c "dbus-launch gio set /home/ga/Desktop/OracleEM.desktop metadata::trusted true" 2>/dev/null || true

# Create utility script for Oracle queries
cat > /usr/local/bin/oracle-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Oracle Database (via Docker)
# Usage: oracle-query "SELECT * FROM employees"
# For HR schema: oracle-query "SELECT * FROM employees" hr
USER="${2:-system}"
PWD_VAR="${3:-OraclePassword123}"
if [ "$USER" = "hr" ]; then
    PWD_VAR="hr123"
fi
sudo docker exec oracle-xe bash -c "echo '$1' | sqlplus -s ${USER}/${PWD_VAR}@localhost:1521/XEPDB1"
DBQUERYEOF
chmod +x /usr/local/bin/oracle-query

# Create sqlplus wrapper
cat > /usr/local/bin/sqlplus-xe << 'SQLPLUSEOF'
#!/bin/bash
# Connect to Oracle XE as specified user
# Usage: sqlplus-xe [user] [password]
USER="${1:-system}"
PWD="${2:-OraclePassword123}"
if [ "$USER" = "hr" ]; then
    PWD="${2:-hr123}"
fi
sudo docker exec -it oracle-xe sqlplus ${USER}/${PWD}@localhost:1521/XEPDB1
SQLPLUSEOF
chmod +x /usr/local/bin/sqlplus-xe

# Install DBeaver if not present
echo "Checking for DBeaver..."
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver Community Edition..."
    snap install dbeaver-ce --classic 2>/dev/null || true
    sleep 5
fi

# Create DBeaver connection configuration directory
DBEAVER_CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
mkdir -p "$DBEAVER_CONFIG_DIR"
chown -R ga:ga "/home/ga/.local/share/DBeaverData" 2>/dev/null || true

# Pre-configure Oracle HR connection for DBeaver
echo "Pre-configuring Oracle HR connection..."
cat > "$DBEAVER_CONFIG_DIR/data-sources.json" << 'DATASOURCES'
{
    "folders": {},
    "connections": {
        "oracle_hr_connection": {
            "provider": "oracle",
            "driver": "oracle_thin",
            "name": "Oracle HR (XEPDB1)",
            "save-password": true,
            "read-only": false,
            "configuration": {
                "host": "localhost",
                "port": "1521",
                "database": "XEPDB1",
                "url": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
                "home": null,
                "type": "dev",
                "auth-model": "native",
                "handlers": {}
            },
            "custom-driver-properties": {},
            "auth-properties": {
                "user": "hr",
                "password": "hr123"
            }
        }
    },
    "connection-types": {
        "dev": {
            "name": "Development",
            "color": "255,255,255",
            "description": "Development environment",
            "auto-commit": true,
            "confirm-execute": false,
            "confirm-data-change": false,
            "auto-close-transactions": false
        }
    }
}
DATASOURCES
chown ga:ga "$DBEAVER_CONFIG_DIR/data-sources.json"

# Create credentials file for the connection
cat > "$DBEAVER_CONFIG_DIR/credentials-config.json" << 'CREDENTIALS'
{
    "oracle_hr_connection": {
        "#connection": {
            "user": "hr",
            "password": "hr123"
        }
    }
}
CREDENTIALS
chown ga:ga "$DBEAVER_CONFIG_DIR/credentials-config.json"

# Start DBeaver for the ga user
echo "Launching DBeaver database GUI..."
su - ga -c "DISPLAY=:1 dbeaver-ce > /tmp/dbeaver.log 2>&1 &" || true

# Wait for DBeaver window to appear (DBeaver takes 30-60 seconds on first launch)
echo "Waiting for DBeaver to start (this may take up to 60 seconds on first launch)..."
sleep 10
GUI_STARTED=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
        GUI_STARTED=true
        echo "DBeaver window detected after $((10 + i))s"
        break
    fi
    sleep 1
done

if [ "$GUI_STARTED" = true ]; then
    echo "DBeaver is starting, waiting for full initialization..."
    sleep 10  # Give DBeaver time to fully render

    # Dismiss initial dialogs using xdotool (Statistics collection, Sample database)
    echo "Checking for initial dialogs..."
    for dialog_attempt in {1..5}; do
        # Check for Statistics collection dialog
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "statistics"; then
            echo "Dismissing Statistics collection dialog..."
            # Press Enter to accept default
            DISPLAY=:1 xdotool key Return
            sleep 2
        fi

        # Check for Sample database dialog
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sample"; then
            echo "Dismissing Sample database dialog..."
            # Press Tab then Enter to select No
            DISPLAY=:1 xdotool key Tab Return
            sleep 2
        fi

        # Check if main window is now active
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver" && ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "statistics|sample|collection"; then
            echo "DBeaver main window is ready"
            break
        fi
        sleep 2
    done

    # Maximize the DBeaver window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "dbeaver" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "DBeaver window maximized"
    fi

    # Take a screenshot to verify state
    DISPLAY=:1 import -window root /tmp/setup_complete_screenshot.png 2>/dev/null || true
    echo "Setup screenshot saved to /tmp/setup_complete_screenshot.png"
else
    echo "WARNING: DBeaver may not have started properly"
fi

echo ""
echo "=== Oracle Database XE Setup Complete ==="
echo ""
echo "Oracle Database XE is running at: localhost:${ORACLE_PORT}"
echo "Oracle EM Express: https://localhost:${EM_PORT}/em/"
echo ""
echo "Login Credentials:"
echo "  System User: system / ${ORACLE_PWD}"
echo "  HR Schema:   hr / hr123"
echo "  PDB Name:    XEPDB1"
echo ""
echo "Database access commands:"
echo "  oracle-query \"SELECT * FROM employees\" hr"
echo "  sqlplus-xe hr"
echo ""
echo "Docker commands:"
echo "  sudo docker logs oracle-xe"
echo "  sudo docker exec -it oracle-xe bash"
echo ""
