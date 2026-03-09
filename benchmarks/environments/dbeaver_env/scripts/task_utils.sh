#!/bin/bash
# Shared utilities for DBeaver tasks

# Database paths
CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"

# Function to query Chinook SQLite database
chinook_query() {
    local query="$1"
    sqlite3 -separator '	' "$CHINOOK_DB" "$query" 2>/dev/null
}

# Function to query with header
chinook_query_header() {
    local query="$1"
    sqlite3 -header -separator '	' "$CHINOOK_DB" "$query" 2>/dev/null
}

# Function to get table count
get_table_count() {
    local table="$1"
    chinook_query "SELECT COUNT(*) FROM $table"
}

# Function to check if file exists and has content
check_file_exists() {
    local filepath="$1"
    local min_size="${2:-10}"  # minimum size in bytes

    if [ -f "$filepath" ]; then
        local size=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)
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
        stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null
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

# Function to check if DBeaver is running
is_dbeaver_running() {
    if pgrep -f "dbeaver" > /dev/null 2>&1; then
        echo "true"
        return 0
    fi
    echo "false"
    return 1
}

# Function to get DBeaver window ID
get_dbeaver_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "dbeaver" | head -1 | awk '{print $1}'
}

# Function to check if a window title contains specific text
window_title_contains() {
    local search_text="$1"
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$search_text"
}

# Function to focus DBeaver window
focus_dbeaver() {
    local wid=$(get_dbeaver_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        return 0
    fi
    return 1
}

# Function to check if database connection exists in DBeaver
# (This checks the DBeaver config files)
check_dbeaver_connection() {
    local db_name="$1"
    local config_dir="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"

    if [ -f "$config_dir/data-sources.json" ]; then
        if grep -qi "$db_name" "$config_dir/data-sources.json" 2>/dev/null; then
            echo "true"
            return 0
        fi
    fi
    echo "false"
    return 1
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
