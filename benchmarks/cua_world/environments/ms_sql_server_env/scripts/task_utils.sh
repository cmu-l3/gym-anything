#!/bin/bash
# Shared utilities for MS SQL Server tasks

# SQL Server configuration
SA_PASSWORD="GymAnything#2024"
MSSQL_CONTAINER="mssql-server"

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Execute SQL query and return results
mssql_query() {
    local query="$1"
    local database="${2:-AdventureWorks2022}"
    docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -d "$database" \
        -Q "$query" -h -1 -W 2>/dev/null
}

# Execute SQL query and return raw output (with headers)
mssql_query_raw() {
    local query="$1"
    local database="${2:-AdventureWorks2022}"
    docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -d "$database" \
        -Q "$query" 2>/dev/null
}

# Count rows from a table
mssql_count() {
    local table="$1"
    local database="${2:-AdventureWorks2022}"
    local count
    count=$(mssql_query "SELECT COUNT(*) FROM $table" "$database" | tr -d ' \r\n')
    echo "$count"
}

# Check if table exists
mssql_table_exists() {
    local table="$1"
    local database="${2:-AdventureWorks2022}"
    local result
    result=$(mssql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$table'" "$database" | tr -d ' \r\n')
    [ "$result" -gt 0 ]
}

# Check if database exists
mssql_database_exists() {
    local database="$1"
    local result
    result=$(docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -Q "SELECT COUNT(*) FROM sys.databases WHERE name = '$database'" -h -1 2>/dev/null | tr -d ' \r\n')
    [ "$result" -gt 0 ]
}

# List all user databases
mssql_list_databases() {
    docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -Q "SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name" -h -1 2>/dev/null
}

# Check if SQL Server is running
mssql_is_running() {
    docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -Q "SELECT 1" 2>/dev/null | grep -q "1"
}

# Get Azure Data Studio windows
get_ads_windows() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "azure|data studio|sql|query"
}

# Check if Azure Data Studio is running
ads_is_running() {
    pgrep -f "azuredatastudio" > /dev/null 2>&1 || \
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"
}
