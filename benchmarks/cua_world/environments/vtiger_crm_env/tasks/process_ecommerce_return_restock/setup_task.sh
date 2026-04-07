#!/bin/bash
echo "=== Setting up process_ecommerce_return_restock task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (used for anti-gaming checks)
date +%s > /tmp/task_start_time.txt
# Convert to MySQL datetime format for easier DB querying
date -d "@$(cat /tmp/task_start_time.txt)" '+%Y-%m-%d %H:%M:%S' > /tmp/task_start_mysql.txt

# 2. Prepare Database Records
echo "Preparing initial database state..."

# 2a. Set up the Product
PID=$(vtiger_db_query "SELECT productid FROM vtiger_products LIMIT 1" | tr -d '[:space:]')
if [ -n "$PID" ]; then
    # Set a specific baseline stock (e.g., 24.000)
    vtiger_db_query "UPDATE vtiger_products SET productname='Solar Pathway Lights (Pack of 6)', qtyinstock=24.000 WHERE productid=$PID"
else
    echo "ERROR: No products found in database to modify."
fi

# 2b. Set up the Contact
CID=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails LIMIT 1" | tr -d '[:space:]')
if [ -n "$CID" ]; then
    vtiger_db_query "UPDATE vtiger_contactdetails SET firstname='Alex', lastname='Mercer' WHERE contactid=$CID"
else
    echo "ERROR: No contacts found in database to modify."
fi

# 2c. Set up the Invoice
IID=$(vtiger_db_query "SELECT invoiceid FROM vtiger_invoice LIMIT 1" | tr -d '[:space:]')
if [ -n "$IID" ]; then
    vtiger_db_query "UPDATE vtiger_invoice SET subject='INV-ECO-994', invoicestatus='Paid', contact_id=$CID WHERE invoiceid=$IID"
else
    echo "ERROR: No invoices found in database to modify."
fi

# 3. Save initial IDs and state for the verifier
echo "$PID" > /tmp/target_pid.txt
echo "$CID" > /tmp/target_cid.txt
echo "$IID" > /tmp/target_iid.txt

INITIAL_QTY=$(vtiger_db_query "SELECT qtyinstock FROM vtiger_products WHERE productid=$PID" | tr -d '[:space:]')
echo "$INITIAL_QTY" > /tmp/initial_qty.txt
echo "Initial Qty in Stock set to: $INITIAL_QTY"

# 4. Ensure Vtiger is accessible, logged in, and at the dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="