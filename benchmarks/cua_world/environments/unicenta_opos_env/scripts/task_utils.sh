#!/bin/bash
# Shared utilities for uniCenta oPOS tasks

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

UNICENTA_DIR=$(cat /tmp/unicenta_install_dir.txt 2>/dev/null || echo "/opt/unicentaopos")
UNICENTA_JAR="$UNICENTA_DIR/unicentaopos.jar"

# -----------------------------------------------------------------------
# MySQL query helpers
# -----------------------------------------------------------------------

# Run a query against the uniCenta database
unicenta_query() {
    local query="$1"
    mysql -u unicenta -punicenta unicentaopos -N -e "$query" 2>/dev/null
}

# Run a query and return single value
unicenta_query_value() {
    local query="$1"
    mysql -u unicenta -punicenta unicentaopos -N -e "$query" 2>/dev/null | head -1 | tr -d '[:space:]'
}

# -----------------------------------------------------------------------
# Process management
# -----------------------------------------------------------------------

# Kill any running uniCenta instance
kill_unicenta() {
    echo "Killing any running uniCenta oPOS..." >&2
    pkill -f "unicentaopos.jar" 2>/dev/null || true
    sleep 2
    pkill -9 -f "unicentaopos.jar" 2>/dev/null || true
    sleep 1
}

# Launch uniCenta as user ga
launch_unicenta() {
    echo "Launching uniCenta oPOS..." >&2
    su - ga -c "setsid /usr/local/bin/unicenta-pos > /tmp/unicenta_task.log 2>&1 &"
}

# Wait for uniCenta window to appear
wait_for_unicenta_window() {
    local timeout=${1:-120}
    local elapsed=0
    echo "Waiting for uniCenta window (timeout: ${timeout}s)..." >&2
    while [ $elapsed -lt $timeout ]; do
        WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "uniCenta" 2>/dev/null | head -1)
        if [ -z "$WID" ]; then
            WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "openbravo" 2>/dev/null | head -1)
        fi
        if [ -n "$WID" ]; then
            echo "uniCenta window found (WID: $WID)" >&2
            return 0
        fi
        # If Java process died, report and stop waiting
        if ! pgrep -f "unicentaopos.jar" > /dev/null 2>&1; then
            echo "WARNING: Java process not running" >&2
            cat /tmp/unicenta_task.log 2>/dev/null | tail -20 >&2
            break
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Timed out waiting for uniCenta window" >&2
    return 1
}

# Get uniCenta window ID
get_unicenta_wid() {
    local wid=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "uniCenta" 2>/dev/null | head -1)
    if [ -z "$wid" ]; then
        wid=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "openbravo" 2>/dev/null | head -1)
    fi
    echo "$wid"
}

# Focus the uniCenta window
focus_unicenta() {
    local wid=$(get_unicenta_wid)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowraise "$wid" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus "$wid" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------
# Screenshot
# -----------------------------------------------------------------------
take_screenshot() {
    local path="${1:-/tmp/unicenta_screen.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
    echo "Screenshot saved: $path" >&2
}

# -----------------------------------------------------------------------
# Database management
# -----------------------------------------------------------------------

# Restore database from backup
restore_database() {
    echo "Restoring database from backup..." >&2
    if [ -f /opt/unicentaopos/unicentaopos_backup.sql ]; then
        mysql -u unicenta -punicenta unicentaopos < /opt/unicentaopos/unicentaopos_backup.sql 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "Database restored successfully" >&2
        else
            echo "WARNING: Database restore may have failed" >&2
        fi
    else
        echo "WARNING: No database backup found" >&2
    fi
}

# Ensure MySQL is running
ensure_mysql_running() {
    if ! mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
        echo "MySQL not running, starting..." >&2
        systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || mysqld_safe &
        sleep 5
        if ! mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
            echo "ERROR: Could not start MySQL" >&2
            return 1
        fi
    fi
    return 0
}

# -----------------------------------------------------------------------
# Full startup sequence
# -----------------------------------------------------------------------

# Start uniCenta and wait for it to be ready
start_unicenta() {
    ensure_mysql_running

    kill_unicenta
    sleep 1
    launch_unicenta
    wait_for_unicenta_window 120
    sleep 8  # extra wait for Java Swing UI to fully render

    # Maximize window
    local wid=$(get_unicenta_wid)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
    fi

    # Focus window safely — click on title bar area (y=30), not center
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 960 30 2>/dev/null || true
    sleep 0.5
    local wid2=$(get_unicenta_wid)
    if [ -n "$wid2" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus "$wid2" 2>/dev/null || true
    fi
    sleep 1

    echo "uniCenta oPOS ready" >&2
}

# Record task start time (for anti-gaming verification)
record_task_start() {
    local path="${1:-/tmp/task_start_time.txt}"
    date +%s > "$path"
}

# -----------------------------------------------------------------------
# Auto-check: ensure MySQL is running when task_utils.sh is sourced
# -----------------------------------------------------------------------
ensure_mysql_running
