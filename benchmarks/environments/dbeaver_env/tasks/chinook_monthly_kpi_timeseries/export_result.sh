#!/bin/bash
echo "=== Exporting Chinook Monthly KPI Result ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/monthly_kpi.csv"
SQL_PATH="/home/ga/Documents/scripts/monthly_kpi.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check 1: DBeaver Connection ---
# Check if 'Chinook' connection exists in DBeaver config
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONNECTION_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Look for name "Chinook" in the json
    if grep -q '"name": "Chinook"' "$DBEAVER_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# --- Check 2: SQL Script ---
SQL_SCRIPT_EXISTS="false"
if [ -f "$SQL_PATH" ] && [ -s "$SQL_PATH" ]; then
    SQL_SCRIPT_EXISTS="true"
fi

# --- Check 3: CSV Existence & Properties ---
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_ROW_COUNT=0
CSV_COL_COUNT=0
CSV_HEADER_VALID="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi

    # Count rows (excluding header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH")
    CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    
    # Count columns
    CSV_COL_COUNT=$(head -1 "$CSV_PATH" | awk -F',' '{print NF}')

    # Check header columns
    HEADER=$(head -1 "$CSV_PATH" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"month"* && "$HEADER" == *"revenue"* && "$HEADER" == *"newcustomers"* && "$HEADER" == *"growth"* ]]; then
        CSV_HEADER_VALID="true"
    fi
fi

# --- Check 4: Data Validation (Ground Truth Calculation) ---
# We compute the ground truth values directly from the DB to compare with CSV

# A. Total Revenue (for checking CumulativeRevenue final value)
GT_TOTAL_REVENUE=$(sqlite3 "$DB_PATH" "SELECT PRINTF('%.2f', TOTAL(Total)) FROM invoices;")

# B. Distinct Months (Expected row count)
GT_MONTH_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(DISTINCT strftime('%Y-%m', InvoiceDate)) FROM invoices;")

# C. Total Distinct Customers (Sum of NewCustomers column should equal this)
GT_TOTAL_CUSTOMERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(DISTINCT CustomerId) FROM invoices;")

# D. First Month Revenue
GT_FIRST_MONTH_REV=$(sqlite3 "$DB_PATH" "SELECT PRINTF('%.2f', TOTAL(Total)) FROM invoices WHERE strftime('%Y-%m', InvoiceDate) = (SELECT MIN(strftime('%Y-%m', InvoiceDate)) FROM invoices);")

# E. Parse Agent's CSV to get their values
AGENT_TOTAL_CUMULATIVE="0"
AGENT_NEW_CUST_SUM="0"
AGENT_FIRST_REV="0"

if [ "$CSV_EXISTS" = "true" ] && [ "$CSV_ROW_COUNT" -gt 0 ]; then
    python3 -c "
import csv
import sys

try:
    with open('$CSV_PATH', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
        # Get headers map (handle case insensitivity)
        headers = {k.lower(): k for k in reader.fieldnames}
        
        rev_col = headers.get('revenue')
        cum_col = headers.get('cumulativerevenue')
        new_col = headers.get('newcustomers')
        
        if not (rev_col and cum_col and new_col):
            print('0|0|0')
            sys.exit(0)

        # 1. Sum of NewCustomers
        new_cust_sum = sum(int(r[new_col]) for r in rows if r[new_col].strip().isdigit())
        
        # 2. Last row Cumulative Revenue
        last_cum = rows[-1][cum_col].replace(',', '')
        
        # 3. First row Revenue
        first_rev = rows[0][rev_col].replace(',', '')
        
        print(f'{last_cum}|{new_cust_sum}|{first_rev}')
except Exception as e:
    print('0|0|0')
" > /tmp/csv_stats.txt

    IFS='|' read -r AGENT_TOTAL_CUMULATIVE AGENT_NEW_CUST_SUM AGENT_FIRST_REV < /tmp/csv_stats.txt
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "sql_script_exists": $SQL_SCRIPT_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_col_count": $CSV_COL_COUNT,
    "csv_header_valid": $CSV_HEADER_VALID,
    "gt_total_revenue": "$GT_TOTAL_REVENUE",
    "gt_month_count": $GT_MONTH_COUNT,
    "gt_total_customers": $GT_TOTAL_CUSTOMERS,
    "gt_first_month_rev": "$GT_FIRST_MONTH_REV",
    "agent_total_cumulative": "$AGENT_TOTAL_CUMULATIVE",
    "agent_new_cust_sum": $AGENT_NEW_CUST_SUM,
    "agent_first_rev": "$AGENT_FIRST_REV",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="