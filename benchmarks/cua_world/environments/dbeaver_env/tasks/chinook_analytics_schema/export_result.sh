#!/bin/bash
# Export script for chinook_analytics_schema task
# Inspects the SQLite database file directly to verify schema and data

echo "=== Exporting Chinook Analytics Schema Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook_analytics.db"
SCRIPT_PATH="/home/ga/Documents/scripts/analytics_schema.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
GT_FILE="/tmp/analytics_gt.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Verify DBeaver Connection ---
CONN_FOUND="false"
CONN_CORRECT_PATH="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Check for connection named 'ChinookAnalytics'
    if grep -q "ChinookAnalytics" "$DBEAVER_CONFIG"; then
        CONN_FOUND="true"
    fi
    # Check if that connection points to the right DB
    # (Simple grep check, python would be more robust but this suffices for bash helper)
    if grep -q "chinook_analytics.db" "$DBEAVER_CONFIG"; then
        CONN_CORRECT_PATH="true"
    fi
fi

# --- 2. Verify View: vw_monthly_revenue ---
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
VIEW_COLS_VALID="false"
VIEW_SPOT_REVENUE=0

if [ -f "$DB_PATH" ]; then
    # Check existence
    if [ "$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='view' AND name='vw_monthly_revenue'")" -eq 1 ]; then
        VIEW_EXISTS="true"
        
        # Check Row Count
        VIEW_ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM vw_monthly_revenue" 2>/dev/null || echo 0)
        
        # Check Columns (dirty check via header)
        COLS=$(sqlite3 -header "$DB_PATH" "SELECT * FROM vw_monthly_revenue LIMIT 1" 2>/dev/null | head -1)
        if [[ "$COLS" == *"Year"* && "$COLS" == *"Month"* && "$COLS" == *"TotalRevenue"* ]]; then
            VIEW_COLS_VALID="true"
        fi

        # Spot Check Revenue
        SPOT_MONTH=$(grep -oP '"spot_check_month": "\K[^"]+' "$GT_FILE")
        # Extract year and month from YYYY-MM
        S_YEAR=$(echo "$SPOT_MONTH" | cut -d'-' -f1)
        S_MONTH=$(echo "$SPOT_MONTH" | cut -d'-' -f2)
        
        VIEW_SPOT_REVENUE=$(sqlite3 "$DB_PATH" "SELECT TotalRevenue FROM vw_monthly_revenue WHERE Year='$S_YEAR' AND Month='$S_MONTH'" 2>/dev/null || echo 0)
    fi
fi

# --- 3. Verify Table: customer_lifetime_value ---
TABLE_EXISTS="false"
TABLE_ROW_COUNT=0
TABLE_COLS_VALID="false"
SEGMENT_HIGH_COUNT=0
SEGMENT_MED_COUNT=0
SEGMENT_LOW_COUNT=0
INDEX_SEG_EXISTS="false"
INDEX_COUNTRY_EXISTS="false"

if [ -f "$DB_PATH" ]; then
    # Check existence
    if [ "$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='customer_lifetime_value'")" -eq 1 ]; then
        TABLE_EXISTS="true"
        
        # Check Row Count
        TABLE_ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM customer_lifetime_value" 2>/dev/null || echo 0)
        
        # Check Columns
        TBL_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(customer_lifetime_value)")
        # Simple string matching for critical columns
        if [[ "$TBL_INFO" == *"CustomerSegment"* && "$TBL_INFO" == *"TotalSpent"* && "$TBL_INFO" == *"AvgInvoiceValue"* ]]; then
            TABLE_COLS_VALID="true"
        fi

        # Check Segments
        SEGMENT_HIGH_COUNT=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM customer_lifetime_value WHERE CustomerSegment='High'" 2>/dev/null || echo 0)
        SEGMENT_MED_COUNT=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM customer_lifetime_value WHERE CustomerSegment='Medium'" 2>/dev/null || echo 0)
        SEGMENT_LOW_COUNT=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM customer_lifetime_value WHERE CustomerSegment='Low'" 2>/dev/null || echo 0)
    fi

    # Check Indexes
    if [ "$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_clv_segment'")" -eq 1 ]; then
        INDEX_SEG_EXISTS="true"
    fi
    if [ "$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_clv_country'")" -eq 1 ]; then
        INDEX_COUNTRY_EXISTS="true"
    fi
fi

# --- 4. Verify SQL Script ---
SCRIPT_EXISTS="false"
SCRIPT_CONTENT_VALID="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    CONTENT=$(cat "$SCRIPT_PATH" | tr '[:lower:]' '[:upper:]')
    # Check for keywords
    if [[ "$CONTENT" == *"CREATE VIEW"* && "$CONTENT" == *"CREATE TABLE"* && "$CONTENT" == *"INSERT"* ]]; then
        SCRIPT_CONTENT_VALID="true"
    fi
fi

# --- 5. Anti-Gaming Timestamp Check ---
DB_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo 0)
if [ "$DB_MTIME" -gt "$TASK_START" ]; then
    DB_MODIFIED="true"
fi

# --- 6. Prepare Result JSON ---
# Read Ground Truth for inclusion
GT_DATA=$(cat "$GT_FILE" 2>/dev/null || echo "{}")

# Create JSON
cat > /tmp/task_result.json << EOF
{
    "timestamp": $(date +%s),
    "task_start": $TASK_START,
    "connection": {
        "found": $CONN_FOUND,
        "correct_path": $CONN_CORRECT_PATH
    },
    "view": {
        "exists": $VIEW_EXISTS,
        "row_count": $VIEW_ROW_COUNT,
        "cols_valid": $VIEW_COLS_VALID,
        "spot_revenue": "$VIEW_SPOT_REVENUE"
    },
    "table": {
        "exists": $TABLE_EXISTS,
        "row_count": $TABLE_ROW_COUNT,
        "cols_valid": $TABLE_COLS_VALID,
        "segment_high": $SEGMENT_HIGH_COUNT,
        "segment_med": $SEGMENT_MED_COUNT,
        "segment_low": $SEGMENT_LOW_COUNT
    },
    "indexes": {
        "segment": $INDEX_SEG_EXISTS,
        "country": $INDEX_COUNTRY_EXISTS
    },
    "script": {
        "exists": $SCRIPT_EXISTS,
        "valid_content": $SCRIPT_CONTENT_VALID
    },
    "anti_gaming": {
        "db_modified": $DB_MODIFIED
    },
    "ground_truth": $GT_DATA
}
EOF

# Safe move
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/task_result.json"