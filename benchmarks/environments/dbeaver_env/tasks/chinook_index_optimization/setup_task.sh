#!/bin/bash
# Setup script for chinook_index_optimization task

set -e
echo "=== Setting up Chinook Index Optimization Task ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
REPORTS_DIR="/home/ga/Documents/reports"

mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove any pre-existing report
rm -f "$REPORTS_DIR/index_report.txt"

# Verify the Chinook database exists
if [ ! -f "$CHINOOK_DB" ]; then
    echo "ERROR: Chinook database not found at $CHINOOK_DB"
    exit 1
fi

# Record baseline indexes (so we can detect NEW indexes created by agent)
echo "Recording baseline indexes..."
BASELINE_INDEXES=$(sqlite3 "$CHINOOK_DB" \
    "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'" \
    2>/dev/null || echo "")
echo "$BASELINE_INDEXES" > /tmp/baseline_chinook_indexes
echo "Baseline indexes:"
echo "$BASELINE_INDEXES"

# Remove any indexes that might have been left from a previous task run
# (only remove custom idx_ style indexes, keep original IFK_ indexes)
sqlite3 "$CHINOOK_DB" << 'SQLEOF'
DROP INDEX IF EXISTS idx_tracks_milliseconds;
DROP INDEX IF EXISTS idx_tracks_unitprice;
DROP INDEX IF EXISTS idx_tracks_duration;
DROP INDEX IF EXISTS idx_tracks_price;
DROP INDEX IF EXISTS idx_tracks_composer;
DROP INDEX IF EXISTS idx_tracks_ms;
DROP INDEX IF EXISTS idx_invoices_date;
DROP INDEX IF EXISTS idx_invoices_invoicedate;
DROP INDEX IF EXISTS idx_invoice_date;
DROP INDEX IF EXISTS idx_inv_date;
DROP INDEX IF EXISTS idx_tracks_genre_composer;
DROP INDEX IF EXISTS idx_tracks_genreid_composer;
SQLEOF

# Re-record baseline after cleanup
BASELINE_INDEXES=$(sqlite3 "$CHINOOK_DB" \
    "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'" \
    2>/dev/null || echo "")
echo "$BASELINE_INDEXES" > /tmp/baseline_chinook_indexes
BASELINE_COUNT=$(echo "$BASELINE_INDEXES" | grep -c "." 2>/dev/null || echo 0)
echo "Baseline index count after cleanup: $BASELINE_COUNT"

# Verify expected columns exist for the slow queries
TRACKS_COLS=$(sqlite3 "$CHINOOK_DB" "PRAGMA table_info(tracks)" 2>/dev/null)
if ! echo "$TRACKS_COLS" | grep -qi "Milliseconds"; then
    echo "ERROR: tracks table missing Milliseconds column"
    exit 1
fi
if ! echo "$TRACKS_COLS" | grep -qi "Composer"; then
    echo "ERROR: tracks table missing Composer column"
    exit 1
fi

INVOICES_COLS=$(sqlite3 "$CHINOOK_DB" "PRAGMA table_info(invoices)" 2>/dev/null)
if ! echo "$INVOICES_COLS" | grep -qi "InvoiceDate"; then
    echo "ERROR: invoices table missing InvoiceDate column"
    exit 1
fi

echo "Schema validation passed."

# Verify the slow queries work (return data)
QUERY_A_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM tracks WHERE Milliseconds BETWEEN 180000 AND 420000 AND UnitPrice = 0.99" 2>/dev/null || echo 0)
QUERY_B_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM invoices WHERE InvoiceDate >= '2011-01-01' AND InvoiceDate < '2013-01-01'" 2>/dev/null || echo 0)
QUERY_C_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM tracks WHERE Composer IS NOT NULL" 2>/dev/null || echo 0)

echo "Slow query result counts: A=$QUERY_A_COUNT, B=$QUERY_B_COUNT, C=$QUERY_C_COUNT"

# Save ground truth for verification
python3 << PYEOF
import json

ground_truth = {
    "baseline_index_count": $BASELINE_COUNT,
    "query_a_result_count": $QUERY_A_COUNT,
    "query_b_result_count": $QUERY_B_COUNT,
    "query_c_result_count": $QUERY_C_COUNT,
    "target_tables_for_indexes": ["tracks", "invoices"],
    "expected_index_keywords": ["milliseconds", "invoicedate", "date", "composer"],
    "min_new_indexes_required": 3
}

with open('/tmp/chinook_index_gt.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)
print("Ground truth saved")
PYEOF

# Record DBeaver connections baseline
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
INITIAL_CONN_COUNT=0
if [ -f "$DBEAVER_CONFIG" ]; then
    INITIAL_CONN_COUNT=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    print(len(config.get('connections', {})))
except:
    print(0)
" 2>/dev/null || echo 0)
fi
echo "$INITIAL_CONN_COUNT" > /tmp/initial_dbeaver_conn_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(date)"

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    sleep 8
fi
focus_dbeaver || true
sleep 2

take_screenshot /tmp/chinook_index_task_start.png
echo "=== Chinook Index Optimization Setup Complete ==="
