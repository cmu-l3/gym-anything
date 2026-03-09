#!/bin/bash
# Setup script for chinook_fraud_investigation task
# Creates a manipulated database with specific financial and geographical anomalies

set -e
echo "=== Setting up Chinook Fraud Investigation Task ==="

source /workspace/scripts/task_utils.sh

# Paths
ORIGINAL_DB="/home/ga/Documents/databases/chinook.db"
FRAUD_DB="/home/ga/Documents/databases/chinook_fraud.db"
EXPORT_DIR="/home/ga/Documents/exports"

# Create directories
mkdir -p "$EXPORT_DIR"
mkdir -p "$(dirname "$FRAUD_DB")"
chown -R ga:ga /home/ga/Documents

# Clean previous artifacts
rm -f "$FRAUD_DB"
rm -f "$EXPORT_DIR/fraud_audit.csv"

# Ensure source DB exists
if [ ! -f "$ORIGINAL_DB" ]; then
    echo "ERROR: Source Chinook database not found at $ORIGINAL_DB"
    exit 1
fi

# 1. Create the Fraud Database
echo "Creating fraud database..."
cp "$ORIGINAL_DB" "$FRAUD_DB"
chown ga:ga "$FRAUD_DB"

# 2. Inject Anomalies using sqlite3
echo "Injecting data anomalies..."

# Anomaly Set 1: Financial Mismatches (Total != Sum of items)
# Invoice 99: Pad the total by +50.00
sqlite3 "$FRAUD_DB" "UPDATE invoices SET Total = Total + 50.00 WHERE InvoiceId = 99;"

# Invoice 256: Pad the total by +10.00
sqlite3 "$FRAUD_DB" "UPDATE invoices SET Total = Total + 10.00 WHERE InvoiceId = 256;"

# Invoice 128: Undercharge by -1.00
sqlite3 "$FRAUD_DB" "UPDATE invoices SET Total = Total - 1.00 WHERE InvoiceId = 128;"

# Anomaly Set 2: Geo Mismatches (BillingCountry != Customer Country)
# Find a customer who is NOT in Cayman Islands
SAFE_CUST=$(sqlite3 "$FRAUD_DB" "SELECT CustomerId FROM customers WHERE Country != 'Cayman Islands' LIMIT 1;")

# Invoice 44 & 300: Change BillingCountry to Cayman Islands
# (Assuming these invoices exist; if not, we pick arbitrary ones, but Chinook 44 and 300 exist)
sqlite3 "$FRAUD_DB" "UPDATE invoices SET BillingCountry = 'Cayman Islands' WHERE InvoiceId IN (44, 300);"
# Ensure the linked customer country is NOT Cayman Islands (it shouldn't be, but let's be safe)
sqlite3 "$FRAUD_DB" "UPDATE customers SET Country = 'USA' WHERE CustomerId IN (SELECT CustomerId FROM invoices WHERE InvoiceId IN (44, 300));"

# 3. Ensure integrity of the REST of the database
# Recalculate totals for all OTHER invoices to ensure no accidental legacy errors
# This ensures 99, 256, 128 are the ONLY financial errors
echo "Normalizing non-fraudulent records..."
sqlite3 "$FRAUD_DB" "
UPDATE invoices 
SET Total = (
    SELECT SUM(UnitPrice * Quantity) 
    FROM invoice_items 
    WHERE invoice_items.InvoiceId = invoices.InvoiceId
)
WHERE InvoiceId NOT IN (99, 128, 256);
"

# 4. Record Timestamp for Anti-Gaming
date +%s > /tmp/task_start_time

# 5. Launch DBeaver (Agent must connect manually)
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            echo "DBeaver started."
            break
        fi
        sleep 1
    done
fi

# Focus and Maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Fraud DB created at: $FRAUD_DB"