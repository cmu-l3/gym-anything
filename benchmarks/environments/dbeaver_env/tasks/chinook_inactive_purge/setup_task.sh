#!/bin/bash
# Setup script for chinook_inactive_purge task
# Prepares the database and calculates ground truth for verification

set -e
echo "=== Setting up Chinook Inactive Purge Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# 1. Reset Database to known state
# We use the standard setup_dbeaver.sh copy, but ensure it's fresh here
if [ -f "/workspace/data/chinook.db" ]; then
    cp /workspace/data/chinook.db "$DB_PATH"
else
    # Fallback if workspace data not found (shouldn't happen in standard env)
    if [ ! -f "$DB_PATH" ]; then
        echo "Error: chinook.db not found and cannot be restored."
        exit 1
    fi
fi
chmod 666 "$DB_PATH"
chown ga:ga "$DB_PATH"

# 2. Calculate Ground Truth (Hidden from Agent)
# Who are the inactive customers? (No invoices in 2013)
# Note: sqlite date comparison works with strings 'YYYY-MM-DD'

echo "Calculating ground truth..."

python3 << 'PYEOF'
import sqlite3
import json

db_path = "/home/ga/Documents/databases/chinook.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# 1. Get ALL Customer IDs
cursor.execute("SELECT CustomerId FROM customers")
all_customers = set(row[0] for row in cursor.fetchall())

# 2. Get Active Customer IDs (Have invoices in 2013)
cursor.execute("SELECT DISTINCT CustomerId FROM invoices WHERE InvoiceDate LIKE '2013-%'")
active_customers = set(row[0] for row in cursor.fetchall())

# 3. Determine Inactive (All - Active)
inactive_customers = list(all_customers - active_customers)
inactive_customers.sort()

# 4. Calculate expected counts for verification
total_customers_initial = len(all_customers)
inactive_count = len(inactive_customers)
active_count = len(active_customers)

# 5. Get sample IDs for detailed verification (one active, one inactive)
sample_inactive = inactive_customers[0] if inactive_customers else None
sample_active = list(active_customers)[0] if active_customers else None

# 6. Calculate orphans that SHOULD be deleted
# Invoices belonging to inactive customers
cursor.execute(f"SELECT COUNT(*) FROM invoices WHERE CustomerId IN ({','.join(map(str, inactive_customers))})")
invoices_to_delete = cursor.fetchone()[0]

# InvoiceItems belonging to those invoices
cursor.execute(f"SELECT COUNT(*) FROM invoice_items WHERE InvoiceId IN (SELECT InvoiceId FROM invoices WHERE CustomerId IN ({','.join(map(str, inactive_customers))}))")
items_to_delete = cursor.fetchone()[0]

ground_truth = {
    "initial_customer_count": total_customers_initial,
    "expected_inactive_count": inactive_count,
    "expected_active_count": active_count,
    "sample_inactive_id": sample_inactive,
    "sample_active_id": sample_active,
    "invoices_to_delete": invoices_to_delete,
    "items_to_delete": items_to_delete,
    "inactive_ids": inactive_customers
}

with open('/tmp/purge_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

print(f"Ground Truth Calculated:")
print(f"  Total Customers: {total_customers_initial}")
print(f"  Inactive (to purge): {inactive_count}")
print(f"  Active (to keep): {active_count}")
PYEOF

# 3. Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# 4. Focus and Screenshot
focus_dbeaver
take_screenshot /tmp/task_start_screenshot.png

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

echo "=== Setup Complete ==="