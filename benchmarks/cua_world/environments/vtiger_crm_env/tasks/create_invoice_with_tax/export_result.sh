#!/bin/bash
echo "=== Exporting create_invoice_with_tax results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_invoice_final.png

# Gather state variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_invoice_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(vtiger_count "vtiger_invoice" "1=1")

# Extract invoice details via SQL
vtiger_db_query "
SELECT 
    i.invoiceid, 
    i.subject, 
    i.invoicedate, 
    i.duedate, 
    i.subtotal, 
    i.total, 
    a.accountname, 
    CONCAT(con.firstname, ' ', con.lastname) as contactname,
    c.createdtime
FROM vtiger_invoice i
INNER JOIN vtiger_crmentity c ON i.invoiceid = c.crmid
LEFT JOIN vtiger_account a ON i.accountid = a.accountid
LEFT JOIN vtiger_contactdetails con ON i.contactid = con.contactid
WHERE c.deleted = 0 AND i.subject = 'INV-2024-GREENFIELD'
ORDER BY i.invoiceid DESC LIMIT 1;
" > /tmp/invoice_data.txt

# Extract line items
INVOICE_ID=$(awk -F'\t' '{print $1}' /tmp/invoice_data.txt | head -n1)

if [ -n "$INVOICE_ID" ]; then
    vtiger_db_query "
    SELECT 
        p.productname, 
        r.quantity, 
        r.listprice 
    FROM vtiger_inventoryproductrel r
    INNER JOIN vtiger_products p ON r.productid = p.productid
    WHERE r.id = $INVOICE_ID
    ORDER BY r.sequence_no ASC;
    " > /tmp/line_items_data.txt
else
    touch /tmp/line_items_data.txt
fi

# Use Python to safely compile the JSON output
python3 - << 'PYEOF'
import json
import os

result = {
    "task_start_time": int(os.popen("cat /tmp/task_start_time.txt 2>/dev/null || echo 0").read().strip()),
    "initial_count": int(os.popen("cat /tmp/initial_invoice_count.txt 2>/dev/null || echo 0").read().strip()),
    "current_count": int(os.popen("cat /tmp/current_invoice_count.txt 2>/dev/null || echo 0").read().strip() or "0"),
    "invoice_found": False,
    "invoice": {},
    "line_items": []
}

try:
    with open('/tmp/invoice_data.txt', 'r') as f:
        inv_line = f.read().strip()
        if inv_line:
            parts = inv_line.split('\t')
            if len(parts) >= 9:
                result["invoice_found"] = True
                result["invoice"] = {
                    "invoiceid": parts[0],
                    "subject": parts[1],
                    "invoicedate": parts[2],
                    "duedate": parts[3],
                    "subtotal": float(parts[4]) if parts[4] else 0.0,
                    "total": float(parts[5]) if parts[5] else 0.0,
                    "accountname": parts[6],
                    "contactname": parts[7],
                    "createdtime": parts[8]
                }
except Exception as e:
    pass

try:
    with open('/tmp/line_items_data.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 3:
                result["line_items"].append({
                    "productname": parts[0],
                    "quantity": float(parts[1]),
                    "listprice": float(parts[2])
                })
except Exception as e:
    pass

with open('/tmp/create_invoice_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/create_invoice_result.json
echo "Result saved to /tmp/create_invoice_result.json"
cat /tmp/create_invoice_result.json
echo "=== create_invoice_with_tax export complete ==="