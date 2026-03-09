#!/bin/bash
# Setup script for chinook_quarterly_trends_analysis
# Prepares DB, cleans state, and computes ground truth

set -e
echo "=== Setting up Chinook Quarterly Trends Analysis ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# 1. Ensure directories exist and are clean
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
rm -f "$EXPORT_DIR/quarterly_trends.csv"
rm -f "$SCRIPTS_DIR/create_trend_view.sql"

# 2. Ensure Chinook DB exists
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Chinook database not found!"
    exit 1
fi

# 3. Clean database state (Drop view if exists from previous run)
sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_quarterly_analytics;"

# 4. Compute Ground Truth values using Python
# We calculate the expected metrics for a specific test quarter (e.g., 2011 Q3) to verify against agent output
echo "Computing ground truth..."
python3 << 'PYEOF'
import sqlite3
import pandas as pd
import json

try:
    conn = sqlite3.connect("/home/ga/Documents/databases/chinook.db")
    
    # Extract raw daily data
    df = pd.read_sql_query("SELECT InvoiceDate, Total FROM invoices", conn)
    
    # Convert date and extract Year/Quarter
    df['InvoiceDate'] = pd.to_datetime(df['InvoiceDate'])
    df['Year'] = df['InvoiceDate'].dt.year
    df['Quarter'] = df['InvoiceDate'].dt.quarter
    
    # Aggregate to Quarterly
    quarterly = df.groupby(['Year', 'Quarter'])['Total'].sum().reset_index()
    quarterly.rename(columns={'Total': 'QuarterlyRevenue'}, inplace=True)
    quarterly = quarterly.sort_values(['Year', 'Quarter'])
    
    # Calculate Window Functions
    quarterly['PrevYearRevenue'] = quarterly['QuarterlyRevenue'].shift(4)
    quarterly['YoYGrowthPct'] = ((quarterly['QuarterlyRevenue'] - quarterly['PrevYearRevenue']) / quarterly['PrevYearRevenue']) * 100
    
    # Rolling 4-quarter average (current + 3 preceding)
    # rolling(4) in pandas includes current row by default. min_periods=1 to match potential SQL behavior or strict?
    # SQL 'ROWS BETWEEN 3 PRECEDING AND CURRENT ROW' requires 4 rows to be full, else partial? 
    # Usually strictly 4 for a "4-quarter rolling avg".
    quarterly['RollingAvgRevenue'] = quarterly['QuarterlyRevenue'].rolling(window=4, min_periods=1).mean()
    
    # Rounding
    quarterly = quarterly.round(2)
    
    # Select a specific test row to verify (e.g., 2011 Q3, or index 10)
    # Using 2011 Q3 (Year 2011, Quarter 3)
    test_row = quarterly[(quarterly['Year'] == 2011) & (quarterly['Quarter'] == 3)].iloc[0]
    
    gt_data = {
        "test_year": int(test_row['Year']),
        "test_quarter": int(test_row['Quarter']),
        "expected_revenue": float(test_row['QuarterlyRevenue']),
        "expected_yoy": float(test_row['YoYGrowthPct']) if pd.notnull(test_row['YoYGrowthPct']) else None,
        "expected_rolling": float(test_row['RollingAvgRevenue']),
        "total_rows": len(quarterly)
    }
    
    with open('/tmp/trends_ground_truth.json', 'w') as f:
        json.dump(gt_data, f)
        
    print("Ground truth calculated:", gt_data)

except Exception as e:
    print(f"Error calculating ground truth: {e}")
    # Fallback default
    with open('/tmp/trends_ground_truth.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

# 5. Record Start Time
date +%s > /tmp/task_start_time.txt

# 6. Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for DBeaver window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "dbeaver"; then
            break
        fi
        sleep 1
    done
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Screenshot initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="