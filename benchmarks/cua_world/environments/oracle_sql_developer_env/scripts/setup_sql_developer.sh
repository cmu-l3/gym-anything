#!/bin/bash
# Oracle SQL Developer Setup Script (post_start hook)
# Starts Oracle XE via Docker, loads HR schema, configures and launches SQL Developer

echo "=== Setting up Oracle SQL Developer Environment ==="

# Configuration
ORACLE_PWD="OraclePassword123"
ORACLE_CONTAINER="oracle-xe"
ORACLE_PORT=1521
HR_USER="hr"
HR_PWD="hr123"

# Wait for desktop
sleep 5

# Function to wait for Oracle to be ready
wait_for_oracle() {
    local timeout=${1:-300}
    local elapsed=0
    local min_wait=90

    echo "Waiting for Oracle Database to be ready (this may take 2-3 minutes)..."
    echo "  Initial wait (${min_wait}s)..."
    sleep $min_wait
    elapsed=$min_wait

    while [ $elapsed -lt $timeout ]; do
        local container_status=$(sudo docker inspect --format='{{.State.Status}}' $ORACLE_CONTAINER 2>/dev/null)
        if [ "$container_status" != "running" ]; then
            echo "  Container not running (status: $container_status)... ${elapsed}s"
            sleep 10
            elapsed=$((elapsed + 10))
            continue
        fi

        echo "  Testing Oracle XEPDB1 connection at ${elapsed}s..."
        local test_output=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s system/${ORACLE_PWD}@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT 1 FROM DUAL;
EXIT;
SQLEOF" 2>&1)

        if echo "$test_output" | grep -q "ORA-"; then
            echo "  Oracle not ready: $(echo "$test_output" | grep "ORA-" | head -1)... ${elapsed}s"
            sleep 10
            elapsed=$((elapsed + 10))
            continue
        fi

        if echo "$test_output" | grep -qE '^\s*1\s*$'; then
            echo "  Oracle listener accepting connections after ${elapsed}s"
            sleep 5
            # Verify stability
            local verify_output=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s system/${ORACLE_PWD}@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM dba_users;
EXIT;
SQLEOF" 2>&1)
            local user_count=$(echo "$verify_output" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')
            if [ -n "$user_count" ] && [ "$user_count" -gt 0 ] 2>/dev/null; then
                echo "Oracle Database XEPDB1 verified ready after ${elapsed}s (found $user_count users)"
                return 0
            fi
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo "ERROR: Oracle readiness check timed out after ${timeout}s"
    return 1
}

# Stop any existing Oracle container
sudo docker stop $ORACLE_CONTAINER 2>/dev/null || true
sudo docker rm $ORACLE_CONTAINER 2>/dev/null || true

# Start Oracle XE container
echo "Starting Oracle Database XE container..."
sudo docker run -d \
    --name $ORACLE_CONTAINER \
    --restart unless-stopped \
    -p ${ORACLE_PORT}:1521 \
    -e ORACLE_PASSWORD=${ORACLE_PWD} \
    -e ORACLE_CHARACTERSET=AL32UTF8 \
    -v oracle_data:/opt/oracle/oradata \
    gvenzl/oracle-xe:21-slim

echo "Container starting..."
sudo docker ps | grep $ORACLE_CONTAINER || true

# Wait for Oracle to be ready
if ! wait_for_oracle 300; then
    echo "CRITICAL ERROR: Oracle Database failed to start!"
    echo "Docker logs:"
    sudo docker logs $ORACLE_CONTAINER 2>&1 | tail -20
    exit 1
fi

# Create HR user with retry logic
echo "Creating HR user and schema..."
HR_USER_CREATED=false
for attempt in {1..3}; do
    echo "  Attempt $attempt to create HR user..."
    HR_CREATE_OUTPUT=$(sudo docker exec -i $ORACLE_CONTAINER sqlplus -s system/${ORACLE_PWD}@localhost:1521/XEPDB1 << 'SQLEOF'
SET HEADING OFF
SET FEEDBACK ON
BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr CASCADE';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

CREATE USER hr IDENTIFIED BY hr123
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION TO hr;
GRANT CREATE TABLE TO hr;
GRANT CREATE VIEW TO hr;
GRANT CREATE SEQUENCE TO hr;
GRANT CREATE PROCEDURE TO hr;
GRANT CREATE TRIGGER TO hr;
GRANT CONNECT, RESOURCE TO hr;

SELECT 'HR_USER_EXISTS' FROM dba_users WHERE username = 'HR';

EXIT;
SQLEOF
    )

    if echo "$HR_CREATE_OUTPUT" | grep -q "HR_USER_EXISTS"; then
        echo "  HR user created successfully"
        HR_USER_CREATED=true
        break
    fi
    sleep 5
done

if [ "$HR_USER_CREATED" != "true" ]; then
    echo "CRITICAL ERROR: Failed to create HR user!"
    exit 1
fi

# Load HR schema data
if [ -f /workspace/data/hr_schema.sql ]; then
    echo "Loading HR schema data..."
    SCHEMA_LOADED=false
    for attempt in {1..3}; do
        echo "  Attempt $attempt to load HR schema..."
        LOAD_OUTPUT=$(sudo docker exec -i $ORACLE_CONTAINER sqlplus -s hr/hr123@localhost:1521/XEPDB1 < /workspace/data/hr_schema.sql 2>&1)

        if echo "$LOAD_OUTPUT" | grep -q "ORA-01017"; then
            echo "  Authentication failed - retrying..."
            sleep 10
            continue
        fi

        # Verify schema loaded
        VERIFY_OUTPUT=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM employees;
EXIT;
SQLEOF" 2>&1)
        SCHEMA_COUNT=$(echo "$VERIFY_OUTPUT" | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')

        if [ -n "$SCHEMA_COUNT" ] && [ "$SCHEMA_COUNT" -gt 0 ] 2>/dev/null; then
            echo "  HR schema loaded: $SCHEMA_COUNT employees"
            SCHEMA_LOADED=true
            break
        fi
        sleep 5
    done

    if [ "$SCHEMA_LOADED" != "true" ]; then
        echo "CRITICAL ERROR: Failed to load HR schema!"
        exit 1
    fi
fi

# Final verification
echo "Final verification of HR schema..."
EMPLOYEE_COUNT=$(sudo docker exec $ORACLE_CONTAINER bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM employees;
EXIT;
SQLEOF" 2>&1 | grep -E '^\s*[0-9]+\s*$' | tr -d '[:space:]')

if [ -z "$EMPLOYEE_COUNT" ] || [ "$EMPLOYEE_COUNT" -lt 100 ] 2>/dev/null; then
    echo "CRITICAL ERROR: HR schema verification failed! Found: ${EMPLOYEE_COUNT:-0}"
    exit 1
fi
echo "HR schema verified: $EMPLOYEE_COUNT employees"

# Create working directories
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/sql_scripts
chown -R ga:ga /home/ga/Documents

# Create utility scripts
cat > /usr/local/bin/oracle-query << 'QUERYEOF'
#!/bin/bash
# Execute SQL query against Oracle Database (via Docker)
# Usage: oracle-query "SELECT * FROM employees" [user] [password]
USER="${2:-hr}"
PWD_VAR="${3:-hr123}"
if [ "$USER" = "system" ]; then
    PWD_VAR="${3:-OraclePassword123}"
fi
sudo docker exec -i oracle-xe bash -c "echo '$1' | sqlplus -s ${USER}/${PWD_VAR}@localhost:1521/XEPDB1"
QUERYEOF
chmod +x /usr/local/bin/oracle-query

cat > /usr/local/bin/sqlplus-xe << 'SQLPLUSEOF'
#!/bin/bash
# Connect to Oracle XE interactively
USER="${1:-hr}"
PWD="${2:-hr123}"
if [ "$USER" = "system" ]; then
    PWD="${2:-OraclePassword123}"
fi
sudo docker exec -it oracle-xe sqlplus ${USER}/${PWD}@localhost:1521/XEPDB1
SQLPLUSEOF
chmod +x /usr/local/bin/sqlplus-xe

# Configure SQL Developer for ga user
echo "Configuring SQL Developer..."
SQLDEVELOPER_CONFIG="/home/ga/.sqldeveloper"
mkdir -p "$SQLDEVELOPER_CONFIG"

# Create user-level product.conf with JVM module-open flags
mkdir -p "$SQLDEVELOPER_CONFIG/24.3.0"
cat > "$SQLDEVELOPER_CONFIG/24.3.0/product.conf" << 'PRODCONFEOF'
SetJavaHome /usr/lib/jvm/java-17-openjdk-amd64
AddVMOption --add-opens=java.base/java.net=ALL-UNNAMED
AddVMOption --add-opens=java.base/java.lang=ALL-UNNAMED
AddVMOption --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED
AddVMOption --add-opens=java.base/sun.net.www=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/sun.awt=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/javax.swing=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/java.awt=ALL-UNNAMED
AddVMOption -Dsun.java2d.xrender=false
AddVMOption -Dsun.java2d.opengl=false
PRODCONFEOF

# Create SQL Developer desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/SQLDeveloper.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Oracle SQL Developer
Comment=Oracle SQL Developer IDE
Exec=/usr/local/bin/sqldeveloper
Icon=/opt/sqldeveloper/icon.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Database;
DESKTOPEOF
chmod +x /home/ga/Desktop/SQLDeveloper.desktop
chown ga:ga /home/ga/Desktop/SQLDeveloper.desktop

# Wait for file to be fully written/synced before trusting
sleep 2

# Mark desktop file as trusted (GNOME requirement) - multiple approaches for reliability
su - ga -c "dbus-launch gio set /home/ga/Desktop/SQLDeveloper.desktop metadata::trusted true" 2>/dev/null || true

# Fallback: set trusted attribute via python3 gio
su - ga -c "python3 -c \"import subprocess; subprocess.run(['gio', 'set', '/home/ga/Desktop/SQLDeveloper.desktop', 'metadata::trusted', 'true'])\"" 2>/dev/null || true

# Fallback: clear immutable flag if set
chattr -i /home/ga/Desktop/SQLDeveloper.desktop 2>/dev/null || true

chown -R ga:ga "$SQLDEVELOPER_CONFIG"

# Launch SQL Developer
echo "Launching Oracle SQL Developer..."
if [ -x "/opt/sqldeveloper/sqldeveloper.sh" ]; then
    # CRITICAL: JAVA_TOOL_OPTIONS with --add-opens prevents JDK 17 module system crashes
    # -Dsun.java2d.xrender=false prevents RenderBadPicture X11 error
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED --add-opens=java.base/sun.net.www=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"

    # Wait for SQL Developer window
    sleep 20
    SQLDEVELOPER_STARTED=false
    for i in {1..120}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            SQLDEVELOPER_STARTED=true
            echo "SQL Developer window detected after $((20 + i))s"
            break
        fi
        sleep 1
    done

    if [ "$SQLDEVELOPER_STARTED" = true ]; then
        sleep 5
        # Maximize window
        WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi

        # Dismiss startup dialogs
        echo "Dismissing initial dialogs..."
        sleep 3
        for i in {1..5}; do
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
            sleep 1
        done

        # Close any update dialogs
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "update\|tip\|welcome"; then
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
            sleep 1
        fi

        echo "SQL Developer ready"
    else
        echo "WARNING: SQL Developer window not detected after 140s"
        echo "Check /tmp/sqldeveloper.log for errors"
    fi
else
    echo "ERROR: SQL Developer not found at /opt/sqldeveloper/sqldeveloper.sh"
    exit 1
fi

# Take setup screenshot
DISPLAY=:1 import -window root /tmp/setup_complete_screenshot.png 2>/dev/null || true

echo ""
echo "=== Oracle SQL Developer Setup Complete ==="
echo ""
echo "Oracle Database XE: localhost:${ORACLE_PORT}"
echo "  System: system / ${ORACLE_PWD}"
echo "  HR Schema: hr / ${HR_PWD}"
echo "  PDB: XEPDB1"
echo "  Employees: $EMPLOYEE_COUNT"
echo ""
echo "SQL Developer: Running"
echo "Export Directory: /home/ga/Documents/exports/"
