#!/bin/bash
# Export script for create_purchase_order
# Extracts PO data from PostgreSQL and saves to JSON

echo "=== Exporting Purchase Order Data ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PO_COUNT=$(cat /tmp/initial_po_count.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Use Python to fetch the latest PO details from the database
# We use python because handling complex SQL results in bash is error-prone
python3 -c "
import json
import psycopg2
import sys
import datetime

def get_db_connection():
    try:
        return psycopg2.connect(host='127.0.0.1', port=65432, user='postgres', dbname='servicedesk')
    except:
        return None

def fetch_po_data():
    conn = get_db_connection()
    if not conn:
        return {'error': 'Database connection failed'}

    cur = conn.cursor()
    
    # Strategy: Find POs created after task start
    # SDP stores time in milliseconds usually
    task_start_ms = $TASK_START * 1000
    
    # Query to fetch PO details
    # Note: Schema is inferred from standard SDP structures. 
    # Adjusting query to be robust: joining PurchaseOrder, PurchaseDefinition (for name), VendorDefinition
    query = \"\"\"
        SELECT 
            po.purchaseorderid,
            pd.name as po_name,
            vd.vendorname,
            po.total_charge,
            po.createdtime,
            po.requireddate
        FROM PurchaseOrder po
        LEFT JOIN PurchaseDefinition pd ON po.purchaseorderid = pd.purchaseorderid
        LEFT JOIN VendorDefinition vd ON po.vendorid = vd.vendorid
        WHERE po.createdtime > %s
        ORDER BY po.createdtime DESC
        LIMIT 1
    \"\"\"
    
    try:
        cur.execute(query, (task_start_ms,))
        row = cur.fetchone()
        
        if not row:
            return {'po_found': False}
            
        po_id, po_name, vendor_name, total, created_time, due_date = row
        
        # Fetch line items for this PO
        # Assuming table PurchaseOrderItems or OrderedItems
        # We try to get item names and prices
        items = []
        try:
            # Try specific SDP table structure for items
            # Usually PurchaseOrder -> PurchaseOrderToLineItem -> PurchaseLineItem
            # Simplified query attempt based on common structures
            cur.execute(\"\"\"
                SELECT quantity, unit_price, description 
                FROM PurchaseLineItem 
                WHERE purchaseorderid = %s
            \"\"\", (po_id,))
            
            # If that fails or returns nothing, we might need to join differently
            # For now, let's assume direct table or simplified view
            item_rows = cur.fetchall()
            for i_row in item_rows:
                items.append({
                    'quantity': float(i_row[0]) if i_row[0] else 0,
                    'price': float(i_row[1]) if i_row[1] else 0.0,
                    'name': i_row[2] # Description/Name
                })
        except Exception as e:
            items_error = str(e)
            # Fallback or retry with different table if needed
            pass

        # Format dates
        created_dt = datetime.datetime.fromtimestamp(created_time/1000.0).isoformat() if created_time else None
        due_dt = datetime.datetime.fromtimestamp(due_date/1000.0).strftime('%Y-%m-%d') if due_date else None

        return {
            'po_found': True,
            'po_id': po_id,
            'po_name': po_name,
            'vendor': vendor_name,
            'total': float(total) if total else 0.0,
            'created_time': created_dt,
            'due_date': due_dt,
            'items': items
        }
        
    except Exception as e:
        return {'error': str(e)}
    finally:
        conn.close()

result = fetch_po_data()

# Add context info
result['task_start'] = $TASK_START
result['initial_count'] = $INITIAL_PO_COUNT

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="