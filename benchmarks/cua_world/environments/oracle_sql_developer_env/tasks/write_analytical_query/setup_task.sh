#!/bin/bash
echo "=== Setting up Dept Salary Analysis Task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# Verify HR schema is correctly populated
HR_CHECK=$(get_table_count "employees" "hr")
if [ -z "$HR_CHECK" ] || [ "$HR_CHECK" = "ERROR" ] || [ "$HR_CHECK" -lt 1 ] 2>/dev/null; then
    echo "ERROR: HR schema not loaded or inaccessible"
    exit 1
fi

# Clean up any potential artifacts and setup directories
mkdir -p /home/ga/Documents/sql_scripts
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/sql_scripts/dept_salary_analysis.sql 2>/dev/null || true
rm -f /home/ga/Documents/exports/dept_salary_report.csv 2>/dev/null || true
chown -R ga:ga /home/ga/Documents

# Ensure HR Database connection is pre-configured
ensure_hr_connection "HR Database" "hr" "hr123"

# Launch SQL Developer if not already running
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Launching SQL Developer..."
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED --add-opens=java.base/sun.net.www=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"
    
    # Wait for the SQL Developer window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            echo "SQL Developer window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Open connection to the HR Database automatically
open_hr_connection_in_sqldeveloper

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial state screenshot for trajectory and verification logs
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="