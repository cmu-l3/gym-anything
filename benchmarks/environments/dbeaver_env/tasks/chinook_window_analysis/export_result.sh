#!/bin/bash
# Export script for chinook_window_analysis task

echo "=== Exporting Chinook Window Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Paths
AGENT_CSV="/home/ga/Documents/exports/monthly_revenue_trends.csv"
AGENT_SQL="/home/ga/Documents/scripts/monthly_revenue_analysis.sql"
GT_CSV="/tmp/ground_truth_monthly_trends.csv"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check DBeaver Connection
CONNECTION_FOUND="false"
CONNECTION_NAME=""
if [ -f "$DBEAVER_CONFIG" ]; then
    # Look for a connection named 'Chinook' pointing to the database
    CONNECTION_INFO=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        data = json.load(f)
    found = False
    name = ''
    for k, v in data.get('connections', {}).items():
        if 'chinook.db' in v.get('configuration', {}).get('database', ''):
            found = True
            name = v.get('name', '')
            if name == 'Chinook':
                break # Exact match
    print(f'{found}|{name}')
except:
    print('False|')
" 2>/dev/null)
    CONNECTION_FOUND=$(echo "$CONNECTION_INFO" | cut -d'|' -f1)
    CONNECTION_NAME=$(echo "$CONNECTION_INFO" | cut -d'|' -f2)
fi

# 2. Check SQL Script
SQL_EXISTS="false"
SQL_CONTENT_VALID="false"
if [ -f "$AGENT_SQL" ]; then
    SQL_EXISTS="true"
    # Check for window function keywords
    KEYWORDS=$(grep -Ei "OVER|LAG|PARTITION|RANK|AVG" "$AGENT_SQL" | wc -l)
    if [ "$KEYWORDS" -ge 1 ]; then
        SQL_CONTENT_VALID="true"
    fi
fi

# 3. Check CSV Existence and Timestamp
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)

if [ -f "$AGENT_CSV" ]; then
    CSV_EXISTS="true"
    FILE_TIME=$(stat -c%Y "$AGENT_CSV" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 4. Detailed Data Verification (Python)
# This compares the agent's CSV against the ground truth CSV
echo "Running data verification..."
VERIFICATION_JSON=$(python3 -c "
import csv
import json
import sys

agent_csv = '$AGENT_CSV'
gt_csv = '$GT_CSV'
result = {
    'headers_match': False,
    'row_count_match': False,
    'revenue_accuracy': 0.0,
    'growth_accuracy': 0.0,
    'moving_avg_accuracy': 0.0,
    'rank_accuracy': 0.0,
    'error': ''
}

try:
    # Read Ground Truth
    with open(gt_csv, 'r') as f:
        gt_rows = list(csv.DictReader(f))

    # Read Agent CSV
    with open(agent_csv, 'r') as f:
        agent_reader = csv.DictReader(f)
        agent_rows = list(agent_reader)
        agent_headers = agent_reader.fieldnames or []

    # 4a. Check Headers
    required = ['YearMonth', 'MonthlyRevenue', 'CumulativeRevenue', 'PrevMonthRevenue', 'MoMGrowthPct', 'MovingAvg3M', 'YearRank']
    # Normalize headers for comparison (case insensitive, ignore spaces)
    agent_headers_norm = [h.lower().replace(' ','') for h in agent_headers]
    required_norm = [h.lower().replace(' ','') for h in required]
    
    missing = [h for h in required_norm if h not in agent_headers_norm]
    if not missing:
        result['headers_match'] = True

    # 4b. Check Row Count (allow +/- 1 for header/newline diffs)
    if abs(len(agent_rows) - len(gt_rows)) <= 1:
        result['row_count_match'] = True

    # 4c. Compare Data Points
    # Create lookup map by YearMonth
    gt_map = {r.get('YearMonth'): r for r in gt_rows if r.get('YearMonth')}
    
    matches_rev = 0
    matches_growth = 0
    matches_ma = 0
    matches_rank = 0
    comparisons = 0

    for a_row in agent_rows:
        ym = a_row.get('YearMonth')
        if not ym or ym not in gt_map:
            continue
            
        comparisons += 1
        gt_row = gt_map[ym]
        
        # Helper for float comparison
        def is_close(v1, v2, tol=0.1): # 0.1 tolerance for float rounding diffs
            try:
                if v1 in [None, '', 'NULL'] and v2 in [None, '', 'NULL']: return True
                f1, f2 = float(v1), float(v2)
                # For large numbers (Revenue), use % diff. For small (Growth), use absolute.
                if abs(f2) > 1000: return abs(f1 - f2) / abs(f2) < 0.01 # 1%
                return abs(f1 - f2) <= tol
            except:
                return False

        # Compare metrics
        if is_close(a_row.get('MonthlyRevenue'), gt_row.get('MonthlyRevenue')):
            matches_rev += 1
        
        if is_close(a_row.get('MoMGrowthPct'), gt_row.get('MoMGrowthPct')):
            matches_growth += 1
            
        if is_close(a_row.get('MovingAvg3M'), gt_row.get('MovingAvg3M')):
            matches_ma += 1
            
        # Rank must be exact
        if str(a_row.get('YearRank')) == str(gt_row.get('YearRank')):
            matches_rank += 1

    if comparisons > 0:
        result['revenue_accuracy'] = matches_rev / comparisons
        result['growth_accuracy'] = matches_growth / comparisons
        result['moving_avg_accuracy'] = matches_ma / comparisons
        result['rank_accuracy'] = matches_rank / comparisons

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
" 2>/dev/null || echo '{"error": "Python script failed"}')

# Assemble final JSON
cat > /tmp/task_result.json << EOF
{
    "connection_found": $( [ "$CONNECTION_FOUND" = "true" ] && echo true || echo false ),
    "connection_name": "$CONNECTION_NAME",
    "sql_exists": $( [ "$SQL_EXISTS" = "true" ] && echo true || echo false ),
    "sql_valid": $( [ "$SQL_CONTENT_VALID" = "true" ] && echo true || echo false ),
    "csv_exists": $( [ "$CSV_EXISTS" = "true" ] && echo true || echo false ),
    "csv_fresh": $( [ "$CSV_CREATED_DURING_TASK" = "true" ] && echo true || echo false ),
    "verification": $VERIFICATION_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json

echo "=== Export Complete ==="