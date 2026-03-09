#!/bin/bash
# Setup for "create_purchase_order" task

echo "=== Setting up Create Purchase Order task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Pre-create the Vendor "Cisco Systems" in the database
# We use direct SQL to ensure it exists for the agent to select.
# Schema assumption: VendorDefinition table holds vendor names.
echo "Ensuring vendor 'Cisco Systems' exists..."

# Check if vendor exists
VENDOR_CHECK=$(sdp_db_exec "SELECT COUNT(*) FROM VendorDefinition WHERE vendorname = 'Cisco Systems';")

if [ "$VENDOR_CHECK" == "0" ]; then
    echo "Creating vendor 'Cisco Systems'..."
    # Insert with a generated ID (using max+1 or a random high number)
    # Note: In a real SDP instance, sequences are used. We'll try a safe approach using python to handle logic.
    python3 -c "
import psycopg2
import time

try:
    conn = psycopg2.connect(host='127.0.0.1', port=65432, user='postgres', dbname='servicedesk')
    cur = conn.cursor()
    
    # Get a new ID
    cur.execute('SELECT MAX(vendorid) FROM VendorDefinition')
    max_id = cur.fetchone()[0]
    if max_id is None: max_id = 0
    new_id = max_id + 1
    
    # Insert Vendor
    cur.execute('INSERT INTO VendorDefinition (vendorid, vendorname, description, status) VALUES (%s, %s, %s, %s)', 
                (new_id, 'Cisco Systems', 'Networking Infrastructure Vendor', 'ACTIVE'))
    
    conn.commit()
    print(f'Vendor created with ID {new_id}')
except Exception as e:
    print(f'Error creating vendor: {e}')
"
else
    echo "Vendor 'Cisco Systems' already exists."
fi

# 3. Record initial PO count for verification
INITIAL_PO_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM PurchaseOrder;")
echo "$INITIAL_PO_COUNT" > /tmp/initial_po_count.txt
echo "Initial PO Count: $INITIAL_PO_COUNT"

# 4. Open Firefox to the home page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Capture initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="