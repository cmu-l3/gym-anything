#!/bin/bash
echo "=== Exporting Chinook AR Workflow Results ==="

# Define paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_PATH="/home/ga/Documents/exports/ar_aging_report.csv"
SCRIPT_PATH="/home/ga/Documents/scripts/ar_setup.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Artifact Existence & Timestamps
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
if [ -f "$EXPORT_PATH" ]; then
    CSV_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# 2. Verify Database State using Python
# We run this verification INSIDE the container to directly access the sqlite DB
# The result is written to a JSON file that the host verifier will read
cat << EOF > /tmp/verify_db_logic.py
import sqlite3
import json
import os
import csv
from datetime import datetime

db_path = "$DB_PATH"
csv_path = "$EXPORT_PATH"
results = {
    "schema_correct": False,
    "rule_pre2013_correct": False,
    "rule_post2013_correct": False,
    "rule_vip_correct": False,
    "report_content_correct": False,
    "errors": []
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # --- Check Schema ---
    cursor.execute("PRAGMA table_info(invoices)")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    
    has_status = "PaymentStatus" in columns
    has_date = "PaymentDate" in columns
    results["schema_correct"] = has_status and has_date
    
    if not results["schema_correct"]:
        results["errors"].append(f"Missing columns. Found: {list(columns.keys())}")

    if results["schema_correct"]:
        # --- Check Rule A: Pre-2013 (Paid, +30 days) ---
        # Sample non-VIP invoices before 2013
        cursor.execute("""
            SELECT InvoiceDate, PaymentStatus, PaymentDate 
            FROM invoices 
            WHERE InvoiceDate < '2013-01-01' AND CustomerId != 5
            LIMIT 5
        """)
        pre_rows = cursor.fetchall()
        
        valid_pre = 0
        for row in pre_rows:
            inv_date_str = row[0].split(' ')[0] # Handle 'YYYY-MM-DD HH:MM:SS'
            pay_status = row[1]
            pay_date_str = row[2]
            
            if pay_status == 'Paid' and pay_date_str:
                # Basic check: verify pay_date > inv_date
                # SQLite date calc is reliable, simple string comparison usually enough for > 
                if pay_date_str > inv_date_str: 
                    valid_pre += 1
        
        results["rule_pre2013_correct"] = (len(pre_rows) > 0 and valid_pre == len(pre_rows))

        # --- Check Rule B: Post-2013 (Pending, NULL) ---
        # Sample non-VIP invoices after 2013
        cursor.execute("""
            SELECT PaymentStatus, PaymentDate 
            FROM invoices 
            WHERE InvoiceDate >= '2013-01-01' AND CustomerId != 5
            LIMIT 5
        """)
        post_rows = cursor.fetchall()
        valid_post = 0
        for row in post_rows:
            if row[0] == 'Pending' and row[1] is None:
                valid_post += 1
        
        results["rule_post2013_correct"] = (len(post_rows) > 0 and valid_post == len(post_rows))

        # --- Check Rule C: VIP Customer 5 (Paid, Same Day) ---
        cursor.execute("""
            SELECT InvoiceDate, PaymentStatus, PaymentDate 
            FROM invoices 
            WHERE CustomerId = 5
        """)
        vip_rows = cursor.fetchall()
        valid_vip = 0
        for row in vip_rows:
            inv_date = row[0].split(' ')[0]
            pay_status = row[1]
            pay_date = row[2]
            # PaymentDate might include time or not depending on agent implementation
            pay_date_clean = pay_date.split(' ')[0] if pay_date else None
            
            if pay_status == 'Paid' and pay_date_clean == inv_date:
                valid_vip += 1
        
        results["rule_vip_correct"] = (len(vip_rows) > 0 and valid_vip == len(vip_rows))

    conn.close()

    # --- Verify CSV Content ---
    if os.path.exists(csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if rows:
                # Check header
                headers = [h.strip() for h in reader.fieldnames]
                required = ['InvoiceId', 'CustomerName', 'InvoiceDate', 'Total', 'DaysOutstanding']
                has_headers = all(any(req.lower() in h.lower() for h in headers) for req in required)
                
                # Check calculation for first row
                first_row = rows[0]
                # Assuming standard format
                try:
                    # Find the DaysOutstanding column
                    days_col = next(h for h in headers if 'days' in h.lower() and 'outstanding' in h.lower())
                    days_val = int(first_row[days_col])
                    results["report_content_correct"] = has_headers and days_val > 0
                except:
                    results["errors"].append("Could not validate CSV content logic")
            else:
                results["errors"].append("CSV file is empty")

except Exception as e:
    results["errors"].append(str(e))

print(json.dumps(results))
EOF

# Execute the python check
DB_CHECK_JSON=$(python3 /tmp/verify_db_logic.py)

# check dbeaver running
APP_RUNNING=$(pgrep -f "dbeaver" > /dev/null && echo "true" || echo "false")

# Compile final result
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "script_exists": $SCRIPT_EXISTS,
    "app_was_running": $APP_RUNNING,
    "db_checks": $DB_CHECK_JSON
}
EOF

# Set permissions for host to read
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Verification data exported to /tmp/task_result.json"