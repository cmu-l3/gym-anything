#!/bin/bash
# Export script for chinook_fts_catalog task
# Verifies database state and export files

echo "=== Exporting FTS Catalog Results ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/fts_final.png

# Initialize results
DBEAVER_CONN_EXISTS="false"
FTS_TABLE_EXISTS="false"
FTS_ROW_COUNT=0
FTS_MATCH_WORKS="false"
SCRIPT_EXISTS="false"
SCRIPT_HAS_KEYWORDS="false"

# 1. Check DBeaver Connection
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Loose check for connection name "Chinook"
    if grep -q '"name": "Chinook"' "$DBEAVER_CONFIG"; then
        DBEAVER_CONN_EXISTS="true"
    fi
fi

# 2. Check Database State (Primary Verification)
if [ -f "$CHINOOK_DB" ]; then
    # Check if table exists
    if sqlite3 "$CHINOOK_DB" "SELECT name FROM sqlite_master WHERE name='catalog_fts';" | grep -q "catalog_fts"; then
        FTS_TABLE_EXISTS="true"
        
        # Check row count
        FTS_ROW_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT count(*) FROM catalog_fts;" 2>/dev/null || echo "0")
        
        # Check if it supports MATCH (proves it's FTS)
        # We try a query that would fail on a normal table if 'MATCH' syntax is used roughly
        # Note: 'MATCH' is standard FTS syntax.
        if sqlite3 "$CHINOOK_DB" "SELECT count(*) FROM catalog_fts WHERE catalog_fts MATCH 'rock';" >/dev/null 2>&1; then
            FTS_MATCH_WORKS="true"
        fi
    fi
fi

# 3. Check CSV Exports
check_csv() {
    local file="$1"
    local path="$EXPORT_DIR/$file"
    local exists="false"
    local rows=0
    local created_during="false"
    
    if [ -f "$path" ]; then
        exists="true"
        # Count data rows (subtract header)
        rows=$(($(wc -l < "$path") - 1))
        
        # Check timestamp
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
    fi
    
    echo "\"$file\": { \"exists\": $exists, \"rows\": $rows, \"fresh\": $created_during }"
}

# 4. Check SQL Script
SCRIPT_PATH="$SCRIPTS_DIR/fts_catalog_setup.sql"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Check for key FTS terms
    if grep -qi "VIRTUAL TABLE" "$SCRIPT_PATH" && grep -qi "fts5" "$SCRIPT_PATH"; then
        SCRIPT_HAS_KEYWORDS="true"
    fi
fi

# Build JSON Result
cat > /tmp/fts_result.json << EOF
{
    "dbeaver_connection_exists": $DBEAVER_CONN_EXISTS,
    "fts_table_exists": $FTS_TABLE_EXISTS,
    "fts_row_count": $FTS_ROW_COUNT,
    "fts_match_functional": $FTS_MATCH_WORKS,
    "csv_files": {
        $(check_csv "search_iron_maiden.csv"),
        $(check_csv "search_blues_rock.csv"),
        $(check_csv "search_bach.csv")
    },
    "sql_script": {
        "exists": $SCRIPT_EXISTS,
        "valid_keywords": $SCRIPT_HAS_KEYWORDS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result:"
cat /tmp/fts_result.json