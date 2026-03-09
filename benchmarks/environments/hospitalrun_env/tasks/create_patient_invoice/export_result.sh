#!/bin/bash
echo "=== Exporting create_patient_invoice results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_invoice_count.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query CouchDB for ALL invoices to analyze in the verifier
# We dump the raw JSON of invoices to be processed by Python
echo "Querying invoices..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# Create a Python script to extract relevant invoice data
cat << 'PYEOF' > /tmp/process_invoices.py
import json
import sys
import time

try:
    with open('/tmp/all_docs.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)

task_start = int(sys.argv[1])
initial_count = int(sys.argv[2])

invoices = []
pricing_items = {}

rows = data.get('rows', [])
current_count = 0

# First pass: collect pricing items to map IDs to names if needed
for row in rows:
    doc = row.get('doc', {})
    doc_id = doc.get('_id', '')
    if doc_id.startswith('pricing_'):
        d = doc.get('data', doc)
        name = d.get('name', '')
        if name:
            pricing_items[doc_id] = name
            pricing_items[doc_id.replace('pricing_p1_', '')] = name # Handle ID variations

# Second pass: collect invoices
for row in rows:
    doc = row.get('doc', {})
    doc_id = doc.get('_id', '')
    
    # Check if it's an invoice
    # HospitalRun invoices usually have ID 'invoice_p1_...' or modelName='invoice'
    d = doc.get('data', doc)
    model = d.get('modelName', doc.get('modelName', ''))
    type_field = d.get('type', doc.get('type', ''))
    
    if doc_id.startswith('invoice_') or model == 'invoice' or type_field == 'invoice':
        current_count += 1
        
        # Check if created/modified after task start
        # CouchDB doesn't strictly enforce timestamps, but HospitalRun usually adds date properties
        # We rely mostly on the count increase + content match for this task
        
        patient = d.get('patient', '')
        line_items = d.get('lineItems', [])
        
        # Normalize line items
        items_summary = []
        for item in line_items:
            name = item.get('name', '')
            # If name is empty, it might reference a pricing item ID
            pricing_id = item.get('id', '')
            if not name and pricing_id in pricing_items:
                name = pricing_items[pricing_id]
                
            qty = item.get('quantity', 0)
            price = item.get('price', 0)
            items_summary.append({
                "name": name,
                "quantity": qty,
                "price": price,
                "raw": item
            })
            
        invoices.append({
            "id": doc_id,
            "patient": patient,
            "status": d.get('status', ''),
            "total": d.get('total', 0),
            "line_items": items_summary,
            "raw_data": d
        })

result = {
    "task_start": task_start,
    "initial_count": initial_count,
    "current_count": current_count,
    "new_invoice_count": current_count - initial_count,
    "invoices": invoices,
    "pricing_lookup": pricing_items
}

print(json.dumps(result))
PYEOF

# Run processing script
python3 /tmp/process_invoices.py "$TASK_START" "$INITIAL_COUNT" > /tmp/task_result.json

# Clean up temp files
rm -f /tmp/all_docs.json /tmp/process_invoices.py

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json | head -c 200
echo "..."