#!/bin/bash
# Export script for chinook_sales_density_analysis
# Verifies database state via sqlite3 queries and checks CSV export

echo "=== Exporting Sales Density Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/sales_density.csv"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Verify DBeaver Connection
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONN_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple check for the name "Chinook" in the config file
    if grep -qi "Chinook" "$DBEAVER_CONFIG"; then
        CONN_EXISTS="true"
    fi
fi

# 2. Verify dim_date Table
DIM_DATE_EXISTS="false"
DIM_DATE_COUNT=0
LEAP_DAY_EXISTS="false"
WEEKEND_CHECK="false"

if [ -f "$DB_PATH" ]; then
    # Check if table exists
    if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='dim_date';" | grep -q "dim_date"; then
        DIM_DATE_EXISTS="true"
        
        # Check row count (Expected 1826)
        DIM_DATE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM dim_date;" 2>/dev/null || echo 0)
        
        # Check specific dates
        # Leap day 2012-02-29
        if [ "$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM dim_date WHERE DateValue LIKE '%2012-02-29%';" 2>/dev/null)" -eq 1 ]; then
            LEAP_DAY_EXISTS="true"
        fi
        
        # Check Weekend Logic: 2009-01-03 was a Saturday (should be IsWeekend=1)
        # 2009-01-05 was a Monday (should be IsWeekend=0)
        SAT_VAL=$(sqlite3 "$DB_PATH" "SELECT IsWeekend FROM dim_date WHERE DateValue LIKE '%2009-01-03%' LIMIT 1;" 2>/dev/null || echo -1)
        MON_VAL=$(sqlite3 "$DB_PATH" "SELECT IsWeekend FROM dim_date WHERE DateValue LIKE '%2009-01-05%' LIMIT 1;" 2>/dev/null || echo -1)
        
        if [ "$SAT_VAL" = "1" ] && [ "$MON_VAL" = "0" ]; then
            WEEKEND_CHECK="true"
        fi
    fi
fi

# 3. Verify View Logic
VIEW_EXISTS="false"
VIEW_VALID="false"
SAMPLE_MONTH_DATA=""

if [ "$DIM_DATE_EXISTS" = "true" ]; then
    if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='view' AND name='v_monthly_density';" | grep -q "v_monthly_density"; then
        VIEW_EXISTS="true"
        
        # Query sample: Jan 2009 (YYYY-MM = '2009-01')
        # In Chinook, Jan 2009 has 31 days.
        # There are invoices on 2009-01-01, 01-02, 01-03, 01-06, 01-11, 01-19... etc.
        # It is NOT full. So ZeroSalesDays should be > 0.
        
        SAMPLE_QUERY="SELECT TotalDays, ZeroSalesDays FROM v_monthly_density WHERE MonthKey='2009-01' LIMIT 1;"
        SAMPLE_MONTH_DATA=$(sqlite3 "$DB_PATH" "$SAMPLE_QUERY" 2>/dev/null || echo "")
        
        # Validate roughly
        if [ -n "$SAMPLE_MONTH_DATA" ]; then
            VIEW_VALID="true"
        fi
    fi
fi

# 4. Verify CSV Export
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_ROW_COUNT=$(wc -l < "$CSV_PATH") # Includes header
    
    FILE_TIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || stat -f%m "$CSV_PATH" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Generate Result JSON
cat > /tmp/density_result.json << EOF
{
    "connection_exists": $CONN_EXISTS,
    "dim_date_exists": $DIM_DATE_EXISTS,
    "dim_date_count": $DIM_DATE_COUNT,
    "leap_day_exists": $LEAP_DAY_EXISTS,
    "weekend_check": $WEEKEND_CHECK,
    "view_exists": $VIEW_EXISTS,
    "view_valid": $VIEW_VALID,
    "sample_month_data": "$SAMPLE_MONTH_DATA",
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated:"
cat /tmp/density_result.json
echo "=== Export Complete ==="