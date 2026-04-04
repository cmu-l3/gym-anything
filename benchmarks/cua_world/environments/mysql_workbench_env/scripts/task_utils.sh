#!/bin/bash
# Shared utilities for MySQL Workbench tasks

# Database credentials
MYSQL_USER="ga"
MYSQL_PASSWORD="password123"
MYSQL_HOST="localhost"

# Directory paths
EXPORT_DIR="/home/ga/Documents/exports"
SQL_SCRIPTS_DIR="/home/ga/Documents/sql_scripts"

# MySQL Workbench config paths
WORKBENCH_CONFIG_DIR="/home/ga/.mysql/workbench"

# Function to execute MySQL query
mysql_query() {
    local database="$1"
    local query="$2"
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -h "$MYSQL_HOST" "$database" -N -e "$query" 2>/dev/null
}

# Function to execute MySQL query with headers
mysql_query_header() {
    local database="$1"
    local query="$2"
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -h "$MYSQL_HOST" "$database" -e "$query" 2>/dev/null
}

# Function to query Sakila database
sakila_query() {
    local query="$1"
    mysql_query "sakila" "$query"
}

# Function to query World database
world_query() {
    local query="$1"
    mysql_query "world" "$query"
}

# Function to get table row count
get_table_count() {
    local database="$1"
    local table="$2"
    mysql_query "$database" "SELECT COUNT(*) FROM $table"
}

# Function to check if file exists and has content
check_file_exists() {
    local filepath="$1"
    local min_size="${2:-10}"  # minimum size in bytes

    if [ -f "$filepath" ]; then
        local size=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null)
        if [ "$size" -ge "$min_size" ]; then
            echo "true"
            return 0
        fi
    fi
    echo "false"
    return 1
}

# Function to get file size in bytes
get_file_size() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null
    else
        echo "0"
    fi
}

# Function to take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Function to check if MySQL Workbench is running
is_workbench_running() {
    if pgrep -f "mysql-workbench" > /dev/null 2>&1; then
        echo "true"
        return 0
    fi
    echo "false"
    return 1
}

# Function to start MySQL Workbench
start_workbench() {
    if [ "$(is_workbench_running)" = "false" ]; then
        su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"
        sleep 10
    fi
}

# Function to get MySQL Workbench window ID
get_workbench_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'
}

# Function to check if a window title contains specific text
window_title_contains() {
    local search_text="$1"
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$search_text"
}

# Function to focus MySQL Workbench window
focus_workbench() {
    local wid=$(get_workbench_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        return 0
    fi
    return 1
}

# Function to find the MySQL Workbench connections file
find_connections_file() {
    # Search in all possible locations
    local found_file=""

    # Check snap locations first (most common for snap installs)
    for dir in /home/ga/snap/mysql-workbench-community/*/; do
        if [ -d "$dir" ]; then
            local check_file=$(find "$dir" -name "connections.xml" 2>/dev/null | head -1)
            if [ -n "$check_file" ] && [ -f "$check_file" ]; then
                found_file="$check_file"
                break
            fi
        fi
    done

    # Check standard location
    if [ -z "$found_file" ] && [ -f "/home/ga/.mysql/workbench/connections.xml" ]; then
        found_file="/home/ga/.mysql/workbench/connections.xml"
    fi

    # Try general find
    if [ -z "$found_file" ]; then
        found_file=$(find /home/ga -name "connections.xml" 2>/dev/null | head -1)
    fi

    echo "$found_file"
}

# Function to check if MySQL connection exists in Workbench config
# MySQL Workbench stores connections in XML files
check_workbench_connection() {
    local connection_name="$1"
    local connections_file=$(find_connections_file)

    if [ -n "$connections_file" ] && [ -f "$connections_file" ]; then
        if grep -qi "$connection_name" "$connections_file" 2>/dev/null; then
            echo "true"
            return 0
        fi
    fi

    echo "false"
    return 1
}

# Function to get list of connections from Workbench config
get_workbench_connections() {
    local connections_file=$(find_connections_file)

    if [ -n "$connections_file" ] && [ -f "$connections_file" ]; then
        # Try to extract connection names from XML
        grep -oP '(?<=<name>)[^<]+' "$connections_file" 2>/dev/null || \
        grep -o '<name>[^<]*</name>' "$connections_file" 2>/dev/null | sed 's/<[^>]*>//g'
    fi
}

# Function to count connections in Workbench
count_workbench_connections() {
    get_workbench_connections | wc -l
}

# Function to parse CSV line count
count_csv_lines() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        # Subtract 1 for header line
        local total=$(wc -l < "$filepath")
        echo $((total - 1))
    else
        echo "0"
    fi
}

# Function to get CSV column count
count_csv_columns() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        head -1 "$filepath" | awk -F',' '{print NF}'
    else
        echo "0"
    fi
}

# Function to check if export file was created recently (within last N seconds)
file_created_recently() {
    local filepath="$1"
    local seconds="${2:-300}"  # default 5 minutes

    if [ -f "$filepath" ]; then
        local file_time=$(stat -c%Y "$filepath" 2>/dev/null || stat -f%m "$filepath" 2>/dev/null)
        local current_time=$(date +%s)
        local age=$((current_time - file_time))

        if [ "$age" -lt "$seconds" ]; then
            echo "true"
            return 0
        fi
    fi
    echo "false"
    return 1
}

# Function to check if MySQL server is running
is_mysql_running() {
    if mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
        echo "true"
        return 0
    fi
    echo "false"
    return 1
}

# Function to get database list
get_databases() {
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e "SHOW DATABASES;" 2>/dev/null
}

# Function to check if database exists
database_exists() {
    local dbname="$1"
    if mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e "SHOW DATABASES LIKE '$dbname';" 2>/dev/null | grep -q "$dbname"; then
        echo "true"
        return 0
    fi
    echo "false"
    return 1
}

# Function to validate CSV content against database
validate_csv_against_db() {
    local csv_file="$1"
    local database="$2"
    local table="$3"
    local column="$4"
    local match_count=0

    if [ ! -f "$csv_file" ]; then
        echo "0"
        return
    fi

    # Skip header and check each value
    while IFS= read -r value; do
        # Clean the value (remove quotes, trim whitespace)
        clean_value=$(echo "$value" | sed 's/^"//;s/"$//' | xargs)
        if [ -n "$clean_value" ]; then
            # Query database to see if value exists
            result=$(mysql_query "$database" "SELECT COUNT(*) FROM $table WHERE $column LIKE '%$clean_value%'")
            if [ "$result" -gt 0 ]; then
                match_count=$((match_count + 1))
            fi
        fi
    done < <(tail -n +2 "$csv_file" | cut -d',' -f1)

    echo "$match_count"
}
