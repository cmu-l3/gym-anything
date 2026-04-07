#!/bin/bash
echo "=== Exporting create_invoice results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather base variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ACCOUNT_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='TechFlow Solutions' AND deleted=0 LIMIT 1" | tr -d '[:space:]')

# 3. Query the invoice data and export to TSV (avoids bash quoting issues)
suitecrm_db_query "SELECT id, billing_account_id, invoice_date, due_date, billing_address_street, billing_address_city, billing_address_state, billing_address_postalcode, billing_address_country, total_amount, UNIX_TIMESTAMP(date_entered) FROM aos_invoices WHERE name='INV-2025-TFS-001' AND deleted=0 ORDER BY date_entered DESC LIMIT 1" > /tmp/inv_data.tsv

# Extract Invoice ID for line items query
I_ID=$(cut -f1 /tmp/inv_data.tsv)

# 4. Query line items related to this invoice
if [ -n "$I_ID" ]; then
    suitecrm_db_query "SELECT name, product_qty, product_unit_price FROM aos_products_quotes WHERE deleted=0 AND (parent_id='${I_ID}' OR group_id IN (SELECT id FROM aos_line_item_groups WHERE parent_id='${I_ID}'))" > /tmp/line_items.tsv
else
    echo "" > /tmp/line_items.tsv
fi

# 5. Build clean JSON output using Python
python3 << EOF
import json
import sys

result = {
    "invoice_found": False,
    "target_account_id": "$TARGET_ACCOUNT_ID",
    "task_start_time": int("$TASK_START") if "$TASK_START".isdigit() else 0,
    "line_items": []
}

# Parse Invoice Data
try:
    with open('/tmp/inv_data.tsv', 'r') as f:
        content = f.read().strip('\n')
        if content:
            fields = content.split('\t')
            if len(fields) >= 11:
                result.update({
                    "invoice_found": True,
                    "invoice_id": fields[0],
                    "billing_account_id": fields[1],
                    "invoice_date": fields[2],
                    "due_date": fields[3],
                    "billing_street": fields[4],
                    "billing_city": fields[5],
                    "billing_state": fields[6],
                    "billing_zip": fields[7],
                    "billing_country": fields[8],
                    "total_amount": fields[9],
                    "date_entered_unix": int(fields[10]) if fields[10].isdigit() else 0
                })
except Exception as e:
    print(f"Error reading invoice data: {e}")

# Parse Line Items Data
try:
    with open('/tmp/line_items.tsv', 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 3:
                result['line_items'].append({
                    'name': parts[0],
                    'qty': parts[1],
                    'price': parts[2]
                })
except Exception as e:
    print(f"Error reading line items data: {e}")

# Write to JSON file
with open('/tmp/create_invoice_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/create_invoice_result.json 2>/dev/null || true
echo "Result saved to /tmp/create_invoice_result.json"
cat /tmp/create_invoice_result.json
echo "=== create_invoice export complete ==="