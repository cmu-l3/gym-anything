#!/bin/bash
echo "=== Exporting create_quote_line_items results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final_state.png

# Read variables
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_QUOTE_COUNT=$(cat /tmp/initial_quote_count.txt 2>/dev/null || echo "0")

# Use Python to safely query the database and export clean JSON
python3 << EOF
import subprocess
import json
import re

def run_db_query(query):
    try:
        # Use \\G for record-based output format which is much easier to parse
        cmd = ['docker', 'exec', 'suitecrm-db', 'mysql', '-u', 'suitecrm', '-psuitecrm_pass', 'suitecrm', '-e', query + '\\G']
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return res.decode('utf-8')
    except Exception as e:
        return ""

def parse_g_format(output):
    """Parses MySQL \G format into a list of dictionaries."""
    records = []
    current_record = {}
    
    for line in output.split('\n'):
        line = line.strip()
        if not line:
            continue
        if line.startswith('***'):
            if current_record:
                records.append(current_record)
                current_record = {}
        elif ':' in line:
            key, val = line.split(':', 1)
            current_record[key.strip()] = val.strip()
            
    if current_record:
        records.append(current_record)
    return records

# 1. Get the quote
quote_raw = run_db_query("SELECT * FROM aos_quotes WHERE name='Q-2024-MER-001' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")
quotes = parse_g_format(quote_raw)
quote_record = quotes[0] if quotes else {}

# 2. If quote exists, get the account name
account_name = ""
if quote_record.get('billing_account_id'):
    acct_raw = run_db_query(f"SELECT name FROM accounts WHERE id='{quote_record['billing_account_id']}'")
    acct_parsed = parse_g_format(acct_raw)
    if acct_parsed:
        account_name = acct_parsed[0].get('name', '')

# 3. If quote exists, get line items
line_items = []
if quote_record.get('id'):
    li_raw = run_db_query(f"SELECT name, product_qty, product_unit_price, product_total_price FROM aos_products_quotes WHERE parent_id='{quote_record['id']}' AND deleted=0")
    line_items = parse_g_format(li_raw)

# 4. Get epoch timestamp of quote creation to check against task start time
quote_epoch = 0
if quote_record.get('id'):
    epoch_raw = run_db_query(f"SELECT UNIX_TIMESTAMP(date_entered) as epoch FROM aos_quotes WHERE id='{quote_record['id']}'")
    epoch_parsed = parse_g_format(epoch_raw)
    if epoch_parsed and epoch_parsed[0].get('epoch'):
        try:
            quote_epoch = int(epoch_parsed[0]['epoch'])
        except ValueError:
            pass

# Assemble final result
result = {
    "task_start_time": int("${TASK_START_TIME}"),
    "initial_quote_count": int("${INITIAL_QUOTE_COUNT}"),
    "quote_found": bool(quote_record),
    "quote_epoch": quote_epoch,
    "quote": {
        "id": quote_record.get('id', ''),
        "name": quote_record.get('name', ''),
        "stage": quote_record.get('stage', ''),
        "valid_until": quote_record.get('valid_until', ''),
        "payment_terms": quote_record.get('payment_terms', ''),
        "total_amount": quote_record.get('total_amount', '0.00'),
        "account_name": account_name
    },
    "line_items": line_items,
    "line_item_count": len(line_items)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result JSON:"
cat /tmp/task_result.json