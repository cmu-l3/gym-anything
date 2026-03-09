#!/bin/bash
# Export script for chinook_daily_revenue_gaps
# Validates the CSV content and SQL script existence

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Paths
CSV_PATH="/home/ga/Documents/exports/daily_revenue_2012.csv"
SQL_PATH="/home/ga/Documents/scripts/date_gap_analysis.sql"
GT_REVENUE_FILE="/tmp/gt_total_revenue.txt"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
CSV_EXISTS="false"
SQL_EXISTS="false"
ROW_COUNT=0
HAS_HEADERS="false"
START_DATE_MATCH="false"
END_DATE_MATCH="false"
LEAP_DAY_FOUND="false"
ZERO_SALES_FOUND="false"
WEEKEND_LOGIC_CORRECT="false"
TOTAL_REVENUE_MATCH="false"
AGENT_REVENUE=0
GT_REVENUE=$(cat "$GT_REVENUE_FILE" 2>/dev/null || echo "0")
DBEAVER_CONN_EXISTS="false"

# Check if SQL script exists
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# Check DBeaver Connection
# Look for a connection that points to chinook.db
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    if grep -q "chinook.db" "$CONFIG_DIR/data-sources.json"; then
        DBEAVER_CONN_EXISTS="true"
    fi
fi

# Check CSV Content using Python for robust parsing
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Analyze CSV content
    # We use python to handle CSV parsing safely
    ANALYSIS=$(python3 -c "
import csv
import sys

csv_path = '$CSV_PATH'
gt_revenue = float($GT_REVENUE)

try:
    with open(csv_path, 'r') as f:
        # Read all lines to check for headers vs data
        lines = f.readlines()
        
    # Check if empty
    if not lines:
        print('rows=0')
        sys.exit(0)
        
    # Heuristic: First line contains 'Date' or 'Total' -> Header
    has_header = 'date' in lines[0].lower() or 'total' in lines[0].lower()
    
    reader = csv.DictReader(lines) if has_header else csv.reader(lines)
    data = list(reader)
    row_count = len(data)
    
    print(f'rows={row_count}')
    print(f'has_header={str(has_header).lower()}')
    
    if row_count == 0:
        sys.exit(0)

    # Normalize column names if DictReader
    if has_header:
        # Map varying column names to standard keys
        normalized_data = []
        fieldnames = [f.lower() for f in reader.fieldnames]
        
        # Identify columns
        date_col = next((f for f in reader.fieldnames if 'date' in f.lower()), None)
        total_col = next((f for f in reader.fieldnames if 'total' in f.lower() or 'rev' in f.lower()), None)
        weekend_col = next((f for f in reader.fieldnames if 'week' in f.lower()), None)
        
        if not date_col or not total_col:
            print('missing_cols=true')
            sys.exit(0)
            
        dates = []
        totals = []
        weekends = []
        
        for row in data:
            dates.append(row[date_col].strip())
            try:
                totals.append(float(row[total_col]))
            except:
                totals.append(0.0)
            if weekend_col:
                weekends.append(row[weekend_col].strip())
                
    else:
        # Assume standard order: Date, Total, Weekend
        dates = [r[0].strip() for r in data]
        totals = []
        for r in data:
            try:
                totals.append(float(r[1]))
            except:
                totals.append(0.0)
        weekends = [r[2].strip() if len(r) > 2 else '' for r in data]

    # Check Date Range
    dates.sort()
    start_match = '2012-01-01' in dates[0]
    end_match = '2012-12-31' in dates[-1]
    leap_day = '2012-02-29' in dates
    
    print(f'start_match={str(start_match).lower()}')
    print(f'end_match={str(end_match).lower()}')
    print(f'leap_day={str(leap_day).lower()}')
    
    # Check Zero Handling (Gap Filling)
    # Finding a day with explicitly 0 revenue
    zeros = [t for t in totals if t == 0.0]
    zero_found = len(zeros) > 0
    print(f'zero_found={str(zero_found).lower()}')
    
    # Check Weekend Logic
    # 2012-01-01 was a Sunday. 2012-01-02 was a Monday.
    # Find index of specific dates
    weekend_correct = False
    try:
        idx_sun = dates.index('2012-01-01')
        idx_mon = dates.index('2012-01-02')
        if weekend_col:
            val_sun = weekends[idx_sun].lower()
            val_mon = weekends[idx_mon].lower()
            # Loose matching for Yes/No/True/False/1/0
            is_sun_yes = val_sun in ['yes', 'y', 'true', '1']
            is_mon_no = val_mon in ['no', 'n', 'false', '0']
            if is_sun_yes and is_mon_no:
                weekend_correct = True
    except ValueError:
        pass
        
    print(f'weekend_correct={str(weekend_correct).lower()}')
    
    # Check Total Revenue matches DB
    total_rev = sum(totals)
    print(f'agent_revenue={total_rev}')
    
    # Tolerance of 1.0 for floating point math
    rev_match = abs(total_rev - gt_revenue) < 1.0
    print(f'revenue_match={str(rev_match).lower()}')

except Exception as e:
    print(f'error={str(e)}')
")
    
    # Parse Python output
    ROW_COUNT=$(echo "$ANALYSIS" | grep "rows=" | cut -d= -f2)
    HAS_HEADERS=$(echo "$ANALYSIS" | grep "has_header=" | cut -d= -f2)
    START_DATE_MATCH=$(echo "$ANALYSIS" | grep "start_match=" | cut -d= -f2)
    END_DATE_MATCH=$(echo "$ANALYSIS" | grep "end_match=" | cut -d= -f2)
    LEAP_DAY_FOUND=$(echo "$ANALYSIS" | grep "leap_day=" | cut -d= -f2)
    ZERO_SALES_FOUND=$(echo "$ANALYSIS" | grep "zero_found=" | cut -d= -f2)
    WEEKEND_LOGIC_CORRECT=$(echo "$ANALYSIS" | grep "weekend_correct=" | cut -d= -f2)
    TOTAL_REVENUE_MATCH=$(echo "$ANALYSIS" | grep "revenue_match=" | cut -d= -f2)
    AGENT_REVENUE=$(echo "$ANALYSIS" | grep "agent_revenue=" | cut -d= -f2)
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "sql_exists": $SQL_EXISTS,
    "dbeaver_connection_exists": $DBEAVER_CONN_EXISTS,
    "row_count": ${ROW_COUNT:-0},
    "start_date_correct": ${START_DATE_MATCH:-false},
    "end_date_correct": ${END_DATE_MATCH:-false},
    "leap_day_present": ${LEAP_DAY_FOUND:-false},
    "gaps_filled_with_zero": ${ZERO_SALES_FOUND:-false},
    "weekend_logic_correct": ${WEEKEND_LOGIC_CORRECT:-false},
    "total_revenue_match": ${TOTAL_REVENUE_MATCH:-false},
    "agent_revenue": ${AGENT_REVENUE:-0},
    "ground_truth_revenue": $GT_REVENUE
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="