#!/bin/bash
# Setup script for chinook_window_analysis task

set -e
echo "=== Setting up Chinook Window Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Directories
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist and are clean
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
rm -f "$EXPORT_DIR/monthly_revenue_trends.csv"
rm -f "$SCRIPTS_DIR/monthly_revenue_analysis.sql"
chown -R ga:ga /home/ga/Documents

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver window
focus_dbeaver

# ------------------------------------------------------------------
# GENERATE GROUND TRUTH
# We use sqlite3 directly to generate the correct CSV for later comparison.
# This ensures we have a baseline for verifying the agent's complex calculations.
# ------------------------------------------------------------------
echo "Generating ground truth data..."

sqlite3 -header -csv "$DB_PATH" "
WITH monthly AS (
    SELECT
        strftime('%Y-%m', InvoiceDate) AS YearMonth,
        ROUND(SUM(Total), 2) AS MonthlyRevenue
    FROM invoices
    GROUP BY strftime('%Y-%m', InvoiceDate)
)
SELECT
    YearMonth,
    MonthlyRevenue,
    ROUND(SUM(MonthlyRevenue) OVER (ORDER BY YearMonth), 2) AS CumulativeRevenue,
    LAG(MonthlyRevenue) OVER (ORDER BY YearMonth) AS PrevMonthRevenue,
    ROUND(
        CASE
            WHEN LAG(MonthlyRevenue) OVER (ORDER BY YearMonth) IS NOT NULL
                 AND LAG(MonthlyRevenue) OVER (ORDER BY YearMonth) != 0
            THEN (MonthlyRevenue - LAG(MonthlyRevenue) OVER (ORDER BY YearMonth))
                 * 100.0
                 / LAG(MonthlyRevenue) OVER (ORDER BY YearMonth)
            ELSE NULL
        END, 2) AS MoMGrowthPct,
    ROUND(AVG(MonthlyRevenue) OVER (
        ORDER BY YearMonth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS MovingAvg3M,
    RANK() OVER (
        PARTITION BY substr(YearMonth, 1, 4)
        ORDER BY MonthlyRevenue DESC
    ) AS YearRank
FROM monthly
ORDER BY YearMonth;
" > /tmp/ground_truth_monthly_trends.csv

chmod 644 /tmp/ground_truth_monthly_trends.csv
GT_LINES=$(wc -l < /tmp/ground_truth_monthly_trends.csv)
echo "Ground truth generated ($GT_LINES lines)"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="