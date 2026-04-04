#!/bin/bash
set -e
echo "=== Exporting Streaming Schema Evolution Result ==="

DB_PATH="/home/ga/Documents/databases/chinook_streaming.db"
SCRIPT_PATH="/home/ga/Documents/scripts/streaming_migration.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Check 1: Database Modification Time ---
DB_MODIFIED="false"
if [ -f "$DB_PATH" ]; then
    DB_MTIME=$(stat -c%Y "$DB_PATH" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
fi

# --- Check 2: DBeaver Connection ---
CONNECTION_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Look for name "ChinookStreaming" in the json file
    if grep -q "ChinookStreaming" "$DBEAVER_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# --- Check 3: Schema & Data Verification (using sqlite3) ---

# Helper function for JSON bool
bool_str() {
    if [ "$1" -gt 0 ]; then echo "true"; else echo "false"; fi
}

if [ -f "$DB_PATH" ]; then
    # Table existence
    HAS_SUB_PLANS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='subscription_plans';" 2>/dev/null)
    HAS_LISTEN_HIST=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='listening_history';" 2>/dev/null)

    # Column existence
    HAS_CUST_COL=$(sqlite3 "$DB_PATH" "PRAGMA table_info(customers);" | grep -i "SubscriptionPlanId" | wc -l)
    HAS_TRACK_COL=$(sqlite3 "$DB_PATH" "PRAGMA table_info(tracks);" | grep -i "PlayCount" | wc -l)

    # Index existence
    HAS_IDX_CUST=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_listening_customer';" 2>/dev/null)
    HAS_IDX_TRACK=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_listening_track';" 2>/dev/null)

    # Data verification: Subscription Plans (Check specific row values)
    # We check for the 3 specific rows. Returns 3 if all match.
    PLAN_DATA_MATCH=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM subscription_plans WHERE (PlanName='Free' AND MonthlyPrice=0.0) OR (PlanName='Premium' AND MonthlyPrice=9.99) OR (PlanName='Family' AND MonthlyPrice=14.99);" 2>/dev/null || echo 0)

    # Default value check (count rows where default was applied)
    # Customers default 1
    CUST_DEFAULT_CHECK=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customers WHERE SubscriptionPlanId = 1;" 2>/dev/null || echo 0)
    CUST_TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customers;" 2>/dev/null || echo 0)
    
    # Tracks default 0
    TRACK_DEFAULT_CHECK=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tracks WHERE PlayCount = 0;" 2>/dev/null || echo 0)
    TRACK_TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tracks;" 2>/dev/null || echo 0)
    
else
    HAS_SUB_PLANS=0
    HAS_LISTEN_HIST=0
    HAS_CUST_COL=0
    HAS_TRACK_COL=0
    HAS_IDX_CUST=0
    HAS_IDX_TRACK=0
    PLAN_DATA_MATCH=0
    CUST_DEFAULT_CHECK=0
    TRACK_DEFAULT_CHECK=0
    CUST_TOTAL=0
    TRACK_TOTAL=0
fi

# --- Check 4: Migration Script ---
SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_PATH" 2>/dev/null || echo 0)
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "db_modified": $DB_MODIFIED,
    "connection_exists": $CONNECTION_EXISTS,
    "table_subscription_plans": $(bool_str $HAS_SUB_PLANS),
    "table_listening_history": $(bool_str $HAS_LISTEN_HIST),
    "column_subscription_plan_id": $(bool_str $HAS_CUST_COL),
    "column_play_count": $(bool_str $HAS_TRACK_COL),
    "index_customer": $(bool_str $HAS_IDX_CUST),
    "index_track": $(bool_str $HAS_IDX_TRACK),
    "plan_data_match_count": $PLAN_DATA_MATCH,
    "cust_default_match_count": $CUST_DEFAULT_CHECK,
    "cust_total_count": $CUST_TOTAL,
    "track_default_match_count": $TRACK_DEFAULT_CHECK,
    "track_total_count": $TRACK_TOTAL,
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json
echo "Export complete. Result:"
cat /tmp/task_result.json