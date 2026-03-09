#!/bin/bash
# Export script for chinook_cohort_retention
# Generates ground truth and packages agent output for verification

echo "=== Exporting results for Chinook Cohort Retention ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
AGENT_CSV="/home/ga/Documents/exports/cohort_retention.csv"
AGENT_SQL="/home/ga/Documents/scripts/cohort_analysis.sql"
AGENT_SUMMARY="/home/ga/Documents/exports/cohort_summary.txt"
GT_JSON="/tmp/cohort_ground_truth.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Generate Ground Truth Data using sqlite3
# We execute the reference query and save output as JSON
echo "Generating ground truth..."

python3 -c "
import sqlite3
import json
import pandas as pd

try:
    conn = sqlite3.connect('$DB_PATH')
    
    query = '''
    WITH first_purchase AS (
        SELECT CustomerId, strftime('%Y-%m', MIN(InvoiceDate)) AS CohortMonth
        FROM invoices GROUP BY CustomerId
    ),
    activity AS (
        SELECT DISTINCT i.CustomerId, fp.CohortMonth,
            (CAST(strftime('%Y', i.InvoiceDate) AS INTEGER) - CAST(substr(fp.CohortMonth,1,4) AS INTEGER)) * 12
            + (CAST(strftime('%m', i.InvoiceDate) AS INTEGER) - CAST(substr(fp.CohortMonth,6,2) AS INTEGER))
            AS MonthNumber
        FROM invoices i JOIN first_purchase fp ON i.CustomerId = fp.CustomerId
    )
    SELECT CohortMonth, MonthNumber,
        (SELECT COUNT(DISTINCT a2.CustomerId) FROM first_purchase a2 WHERE a2.CohortMonth = a.CohortMonth) AS CohortSize,
        COUNT(DISTINCT CustomerId) AS ActiveCustomers,
        ROUND(COUNT(DISTINCT CustomerId) * 100.0 / 
                (SELECT COUNT(DISTINCT a2.CustomerId) FROM first_purchase a2 WHERE a2.CohortMonth = a.CohortMonth), 1) AS RetentionPct
    FROM activity a
    GROUP BY CohortMonth, MonthNumber
    HAVING ActiveCustomers > 0
    ORDER BY CohortMonth, MonthNumber;
    '''
    
    df = pd.read_sql_query(query, conn)
    
    # Save as JSON records for easy comparison
    result = {
        'row_count': len(df),
        'columns': df.columns.tolist(),
        'data': df.to_dict(orient='records'),
        'total_cohorts': df['CohortMonth'].nunique(),
        'max_cohort_month': df.loc[df['CohortSize'].idxmax()]['CohortMonth'],
        'max_cohort_size': int(df['CohortSize'].max())
    }
    
    with open('$GT_JSON', 'w') as f:
        json.dump(result, f)
        
    print('Ground truth generated successfully.')
    
except Exception as e:
    print(f'Error generating ground truth: {e}')
    # Create empty structure on failure
    with open('$GT_JSON', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# 2. Check Agent Files
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

# Check CSV
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
CSV_SIZE=0

if [ -f "$AGENT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$AGENT_CSV")
    CSV_MTIME=$(stat -c%Y "$AGENT_CSV")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

# Check SQL
SQL_EXISTS="false"
if [ -f "$AGENT_SQL" ]; then
    SQL_EXISTS="true"
fi

# Check Summary
SUMMARY_EXISTS="false"
if [ -f "$AGENT_SUMMARY" ]; then
    SUMMARY_EXISTS="true"
fi

# 3. Check DBeaver Connection
# Look for 'ChinookCohort' in data-sources.json
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONNECTION_FOUND="false"

if [ -f "$CONFIG_FILE" ]; then
    if grep -q "ChinookCohort" "$CONFIG_FILE"; then
        CONNECTION_FOUND="true"
    fi
fi

# 4. Package everything into result JSON
TEMP_RESULT="/tmp/task_result.json"

cat > "$TEMP_RESULT" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "csv_size": $CSV_SIZE,
    "sql_exists": $SQL_EXISTS,
    "summary_exists": $SUMMARY_EXISTS,
    "connection_found": $CONNECTION_FOUND,
    "agent_csv_path": "$AGENT_CSV",
    "ground_truth_path": "$GT_JSON"
}
EOF

# Ensure permissions for verification reading
chmod 644 "$TEMP_RESULT"
chmod 644 "$GT_JSON" 2>/dev/null || true
if [ -f "$AGENT_CSV" ]; then
    chmod 644 "$AGENT_CSV"
fi

echo "Export complete. Result saved to $TEMP_RESULT"