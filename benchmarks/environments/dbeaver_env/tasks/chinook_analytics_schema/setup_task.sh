#!/bin/bash
# Setup script for chinook_analytics_schema task
# Prepares the analytics database copy and computes ground truth

set -e
echo "=== Setting up Chinook Analytics Schema Task ==="

source /workspace/scripts/task_utils.sh

SOURCE_DB="/home/ga/Documents/databases/chinook.db"
TARGET_DB="/home/ga/Documents/databases/chinook_analytics.db"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$(dirname "$TARGET_DB")"
mkdir -p "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# 1. Prepare the database
if [ ! -f "$SOURCE_DB" ]; then
    echo "ERROR: Source Chinook database not found at $SOURCE_DB"
    # Fallback download if needed (should be handled by env setup, but safety first)
    wget -q -O "$SOURCE_DB" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi

echo "Creating working copy of database..."
cp "$SOURCE_DB" "$TARGET_DB"
chown ga:ga "$TARGET_DB"
chmod 644 "$TARGET_DB"

# Ensure it's clean (remove objects if they somehow exist from previous runs)
sqlite3 "$TARGET_DB" "DROP VIEW IF EXISTS vw_monthly_revenue;" 2>/dev/null || true
sqlite3 "$TARGET_DB" "DROP TABLE IF EXISTS customer_lifetime_value;" 2>/dev/null || true
sqlite3 "$TARGET_DB" "DROP INDEX IF EXISTS idx_clv_segment;" 2>/dev/null || true
sqlite3 "$TARGET_DB" "DROP INDEX IF EXISTS idx_clv_country;" 2>/dev/null || true

# 2. Compute Ground Truth (using the source DB to calculate what we expect)
echo "Computing ground truth values..."

# GT for View: Count of Year-Month combinations
GT_MONTH_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(DISTINCT strftime('%Y-%m', InvoiceDate)) FROM invoices;")

# GT for View: Total Revenue for a specific month (e.g., 2010-02) to spot check
# Note: SQLite sample data might vary slightly, so we calculate dynamic GT
SPOT_CHECK_MONTH="2010-02"
GT_SPOT_REVENUE=$(sqlite3 "$TARGET_DB" "SELECT SUM(Total) FROM invoices WHERE strftime('%Y-%m', InvoiceDate) = '$SPOT_CHECK_MONTH';")

# GT for Table: Total Customers
GT_CUSTOMER_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers;")

# GT for Table: Segment Counts
# High: >= 40, Medium: >= 20 & < 40, Low: < 20
GT_HIGH_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM (SELECT SUM(Total) as s FROM invoices GROUP BY CustomerId HAVING s >= 40);")
GT_MED_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM (SELECT SUM(Total) as s FROM invoices GROUP BY CustomerId HAVING s >= 20 AND s < 40);")
GT_LOW_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM (SELECT CustomerId FROM customers WHERE CustomerId NOT IN (SELECT CustomerId FROM invoices) UNION SELECT CustomerId FROM invoices GROUP BY CustomerId HAVING SUM(Total) < 20);")

# Save GT to JSON for export script / verifier
cat > /tmp/analytics_gt.json << EOF
{
    "month_count": $GT_MONTH_COUNT,
    "spot_check_month": "$SPOT_CHECK_MONTH",
    "spot_check_revenue": ${GT_SPOT_REVENUE:-0},
    "customer_count": $GT_CUSTOMER_COUNT,
    "high_segment_count": $GT_HIGH_COUNT,
    "medium_segment_count": $GT_MED_COUNT,
    "low_segment_count": $GT_LOW_COUNT
}
EOF

# 3. Task Start Timestamp
date +%s > /tmp/task_start_time.txt

# 4. Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "Setup complete. GT saved to /tmp/analytics_gt.json"