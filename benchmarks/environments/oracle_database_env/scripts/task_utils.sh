#!/bin/bash
# Shared utilities for Oracle Database task setup and export scripts

# Oracle connection parameters
ORACLE_CONTAINER="oracle-xe"
ORACLE_PORT=1521
ORACLE_PDB="XEPDB1"
SYSTEM_PWD="OraclePassword123"
HR_PWD="hr123"

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 30)
# Returns: 0 if found, 1 if timeout
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s"
    return 1
}

# Wait for a file to be created or modified
# Args: $1 - file path
#       $2 - timeout in seconds (default: 10)
# Returns: 0 if file exists, 1 if timeout
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            echo "File ready: $filepath"
            return 0
        fi
        sleep 0.5
    done

    echo "Timeout: File not found: $filepath"
    return 1
}

# Focus a window and verify it was focused
# Args: $1 - window ID or name pattern
# Returns: 0 if focused successfully, 1 otherwise
focus_window() {
    local window_id="$1"

    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        echo "Window focused: $window_id"
        return 0
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Execute SQL query against Oracle Database (via Docker)
# Args: $1 - SQL query
#       $2 - user (default: hr)
#       $3 - password (default: hr123)
# Returns: query result
oracle_query() {
    local query="$1"
    local user="${2:-hr}"
    local pwd="${3:-$HR_PWD}"

    if [ "$user" = "system" ]; then
        pwd="${3:-$SYSTEM_PWD}"
    fi

    # Use here-string to avoid issues with special characters in SQL
    sudo docker exec -i $ORACLE_CONTAINER sqlplus -s "${user}/${pwd}@localhost:${ORACLE_PORT}/${ORACLE_PDB}" << EOSQL
$query
EOSQL
}

# Execute SQL query and return only data (no headers or formatting)
# Args: $1 - SQL query
#       $2 - user (default: hr)
# Returns: query result (or "ERROR" if query fails)
oracle_query_raw() {
    local query="$1"
    local user="${2:-hr}"
    local pwd="$HR_PWD"

    if [ "$user" = "system" ]; then
        pwd="$SYSTEM_PWD"
    fi

    # Use here-document to properly pass SQL with settings
    local result=$(sudo docker exec -i $ORACLE_CONTAINER sqlplus -s "${user}/${pwd}@localhost:${ORACLE_PORT}/${ORACLE_PDB}" << EOSQL 2>&1
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767
$query
EOSQL
    )

    # Check for ORA- errors in output
    if echo "$result" | grep -q "ORA-"; then
        echo "ERROR: $(echo "$result" | grep "ORA-" | head -1)" >&2
        echo "ERROR"
        return 1
    fi

    # Return clean result
    echo "$result" | grep -v '^$'
}

# Get count from a table
# Args: $1 - table name
#       $2 - user (default: hr)
get_table_count() {
    local table="$1"
    local user="${2:-hr}"

    oracle_query_raw "SELECT COUNT(*) FROM $table;" "$user" | tr -d ' '
}

# Check if a record exists
# Args: $1 - table name
#       $2 - where clause
#       $3 - user (default: hr)
# Returns: 0 if exists, 1 if not
record_exists() {
    local table="$1"
    local where_clause="$2"
    local user="${3:-hr}"

    local count=$(oracle_query_raw "SELECT COUNT(*) FROM $table WHERE $where_clause;" "$user" | tr -d ' ')
    [ "${count:-0}" -gt 0 ]
}

# Get employee count from HR schema
get_employee_count() {
    get_table_count "employees" "hr"
}

# Get department count from HR schema
get_department_count() {
    get_table_count "departments" "hr"
}

# Check if employee exists by ID
# Args: $1 - employee_id
# Returns: 0 if found, 1 if not found
employee_exists() {
    local emp_id="$1"
    record_exists "employees" "employee_id = $emp_id" "hr"
}

# Check if employee exists by name
# Args: $1 - first_name
#       $2 - last_name
# Returns: 0 if found, 1 if not found
employee_exists_by_name() {
    local fname="$1"
    local lname="$2"
    record_exists "employees" "LOWER(TRIM(first_name))='$(echo $fname | tr '[:upper:]' '[:lower:]')' AND LOWER(TRIM(last_name))='$(echo $lname | tr '[:upper:]' '[:lower:]')'" "hr"
}

# Get employee details by ID
# Args: $1 - employee_id
# Returns: tab-separated employee data
get_employee() {
    local emp_id="$1"
    oracle_query_raw "SELECT employee_id, first_name, last_name, email, phone_number, hire_date, job_id, salary, department_id FROM employees WHERE employee_id = $emp_id;" "hr"
}

# Get the maximum employee ID
get_max_employee_id() {
    oracle_query_raw "SELECT NVL(MAX(employee_id), 0) FROM employees;" "hr" | tr -d ' '
}

# Take a screenshot
# Args: $1 - output file path (default: /tmp/screenshot.png)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f focus_window
export -f oracle_query
export -f oracle_query_raw
export -f get_table_count
export -f record_exists
export -f get_employee_count
export -f get_department_count
export -f employee_exists
export -f employee_exists_by_name
export -f get_employee
export -f get_max_employee_id
export -f take_screenshot

# Export variables
export ORACLE_CONTAINER
export ORACLE_PORT
export ORACLE_PDB
export SYSTEM_PWD
export HR_PWD
