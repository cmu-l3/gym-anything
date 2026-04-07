#!/bin/bash
# Shared utilities for Oracle SQL Developer environment tasks

# Oracle connection parameters
ORACLE_CONTAINER="oracle-xe"
ORACLE_PORT=1521
ORACLE_PDB="XEPDB1"
SYSTEM_PWD="OraclePassword123"
HR_PWD="hr123"
REPORT_USER_PWD="Report2024"

# Execute SQL query against Oracle Database (via Docker)
oracle_query() {
    local query="$1"
    local user="${2:-hr}"
    local pwd="${3:-$HR_PWD}"
    if [ "$user" = "system" ]; then
        pwd="${3:-$SYSTEM_PWD}"
    elif [ "$user" = "report_user" ]; then
        pwd="${3:-$REPORT_USER_PWD}"
    fi
    sudo docker exec -i $ORACLE_CONTAINER sqlplus -s "${user}/${pwd}@localhost:${ORACLE_PORT}/${ORACLE_PDB}" << EOSQL
$query
EOSQL
}

# Execute SQL query returning only data (no headers/formatting)
oracle_query_raw() {
    local query="$1"
    local user="${2:-hr}"
    local pwd="$HR_PWD"
    if [ "$user" = "system" ]; then
        pwd="$SYSTEM_PWD"
    fi
    local result=$(sudo docker exec -i $ORACLE_CONTAINER sqlplus -s "${user}/${pwd}@localhost:${ORACLE_PORT}/${ORACLE_PDB}" << EOSQL 2>&1
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767
$query
EOSQL
    )
    if echo "$result" | grep -q "ORA-"; then
        echo "ERROR: $(echo "$result" | grep "ORA-" | head -1)" >&2
        echo "ERROR"
        return 1
    fi
    echo "$result" | grep -v '^$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Get count from a table
get_table_count() {
    local table="$1"
    local user="${2:-hr}"
    oracle_query_raw "SELECT COUNT(*) FROM $table;" "$user" | tr -d '[:space:]'
}

# Check if a record exists
record_exists() {
    local table="$1"
    local where_clause="$2"
    local user="${3:-hr}"
    local count=$(oracle_query_raw "SELECT COUNT(*) FROM $table WHERE $where_clause;" "$user" | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

# Wait for a window with specified title
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Focus a window by ID or name
focus_window() {
    local window_id="$1"
    DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null
}

# Take a screenshot
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || true
}

# Get employee count
get_employee_count() {
    get_table_count "employees" "hr"
}

# Get max employee ID
get_max_employee_id() {
    oracle_query_raw "SELECT NVL(MAX(employee_id), 0) FROM employees;" "hr" | tr -d '[:space:]'
}

# Collect SQL Developer GUI usage evidence
# Returns JSON fragment with gui_evidence fields
collect_gui_evidence() {
    local task_start_time=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

    # 1. Check SqlHistory directory for SQL statements executed via GUI worksheet
    local sql_history_count=0
    local sql_history_dir="/home/ga/.sqldeveloper/SqlHistory"
    if [ -d "$sql_history_dir" ]; then
        # Count history files modified after task start
        sql_history_count=$(find "$sql_history_dir" -name "*.xml" -type f -newer /home/ga/.task_start_time 2>/dev/null | wc -l)
    fi

    # 2. Check MRUConnectionCache in product-preferences.xml
    local mru_connection_count=0
    local prefs_file=$(find /home/ga/.sqldeveloper/system*/o.sqldeveloper -name "product-preferences.xml" -type f 2>/dev/null | head -1)
    if [ -n "$prefs_file" ] && [ -f "$prefs_file" ]; then
        mru_connection_count=$(grep -c "IdeConnections#" "$prefs_file" 2>/dev/null || true)
    fi

    # 3. Check window title changed from Welcome Page (proves GUI interaction)
    local window_title=""
    local title_changed=false
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
        window_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "sql developer|oracle sql" | head -1 | sed 's/^[^ ]* *[^ ]* *[^ ]* *//')
        if echo "$window_title" | grep -qvi "Welcome Page"; then
            title_changed=true
        fi
    fi

    # 4. Check for active Oracle sessions from SQL Developer (not sqlplus)
    local sqldev_sessions=0
    sqldev_sessions=$(oracle_query_raw "SELECT COUNT(*) FROM v\$session WHERE username = 'HR' AND UPPER(program) LIKE '%SQL DEVELOPER%';" "system" 2>/dev/null | tr -d '[:space:]')
    # Sanitize: ensure numeric (Docker errors can produce non-numeric strings)
    if ! [[ "$sqldev_sessions" =~ ^[0-9]+$ ]]; then sqldev_sessions=0; fi
    if ! [[ "$sql_history_count" =~ ^[0-9]+$ ]]; then sql_history_count=0; fi
    if ! [[ "$mru_connection_count" =~ ^[0-9]+$ ]]; then mru_connection_count=0; fi

    # Output JSON fragment
    echo "\"gui_evidence\": {"
    echo "    \"sql_history_count\": ${sql_history_count:-0},"
    echo "    \"mru_connection_count\": ${mru_connection_count:-0},"
    echo "    \"window_title\": \"$(echo "$window_title" | sed 's/"/\\"/g')\","
    echo "    \"window_title_changed\": $title_changed,"
    echo "    \"sqldev_oracle_sessions\": ${sqldev_sessions:-0}"
    echo "}"
}

# Pre-configure HR Database connection in SQL Developer so tasks 2-7 don't start at Welcome Page
ensure_hr_connection() {
    local conn_name="${1:-HR Database}"
    local username="${2:-hr}"
    local password="${3:-$HR_PWD}"

    # Find or create the connections directory
    local SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
    if [ -z "$SQLDEVELOPER_SYSTEM_DIR" ]; then
        echo "WARNING: SQL Developer system dir not found, cannot pre-configure connection"
        return 1
    fi

    local CONN_DIR=$(find "$SQLDEVELOPER_SYSTEM_DIR" -name "o.jdeveloper.db.connection*" -type d 2>/dev/null | head -1)
    if [ -z "$CONN_DIR" ]; then
        CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
        mkdir -p "$CONN_DIR"
    fi

    local CONN_FILE="$CONN_DIR/connections.json"

    # Only create if no connection exists yet
    if [ -f "$CONN_FILE" ] && grep -q '"name"' "$CONN_FILE" 2>/dev/null; then
        echo "Connection already configured in $CONN_FILE"
        return 0
    fi

    cat > "$CONN_FILE" << CONNEOF
{
  "connections": [
    {
      "name": "$conn_name",
      "type": "jdbc",
      "info": {
        "role": "",
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "RaptorConnectionType": "Oracle",
        "customUrl": "jdbc:oracle:thin:@localhost:${ORACLE_PORT}/${ORACLE_PDB}",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "${ORACLE_PORT}",
        "subtype": "oraJDBC",
        "ConnName": "$conn_name",
        "serviceName": "${ORACLE_PDB}",
        "user": "$username",
        "password": "$password"
      }
    }
  ]
}
CONNEOF
    chown ga:ga "$CONN_FILE"
    echo "Pre-configured connection '$conn_name' in $CONN_FILE"
    return 0
}

# Open the pre-configured connection in SQL Developer so agent sees connected state
open_hr_connection_in_sqldeveloper() {
    if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
        echo "WARNING: SQL Developer not running, skipping connection open"
        return 1
    fi

    # Focus SQL Developer
    local WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 1
    fi

    # Check if already connected (title != Welcome Page and != just "Oracle SQL Developer")
    local cur_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "sql developer|oracle sql" | head -1 | sed 's/^[^ ]* *[^ ]* *[^ ]* *//')
    if echo "$cur_title" | grep -qi "HR Database"; then
        echo "SQL Developer already connected to HR Database"
        return 0
    fi

    # Double-click the HR Database connection in the Connections panel to open it
    # The connection node is typically at the top-left of the panel
    # First try clicking the Connections panel area, then the connection name
    DISPLAY=:1 xdotool mousemove 150 153 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool click --repeat 2 --delay 100 1 2>/dev/null || true
    sleep 5

    # Check if connection dialog appeared (needs password)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "connection\|password\|select database"; then
        # The password dialog may appear - press Enter to accept saved password
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 3
    fi

    return 0
}

# Export functions and variables
export -f oracle_query oracle_query_raw get_table_count record_exists
export -f wait_for_window focus_window take_screenshot
export -f get_employee_count get_max_employee_id collect_gui_evidence
export -f ensure_hr_connection open_hr_connection_in_sqldeveloper
export ORACLE_CONTAINER ORACLE_PORT ORACLE_PDB SYSTEM_PWD HR_PWD REPORT_USER_PWD
