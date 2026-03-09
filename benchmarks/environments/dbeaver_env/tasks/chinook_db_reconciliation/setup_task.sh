#!/bin/bash
set -e
echo "=== Setting up Chinook DB Reconciliation Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

CHINOOK_SRC="/home/ga/Documents/databases/chinook.db"
PROD_DB="/home/ga/Documents/databases/chinook_prod.db"
SNAPSHOT_DB="/home/ga/Documents/databases/chinook_snapshot.db"
GT_FILE="/tmp/reconciliation_ground_truth.json"

# Ensure directories exist
mkdir -p /home/ga/Documents/scripts
mkdir -p /home/ga/Documents/exports

# Ensure source Chinook DB exists
if [ ! -f "$CHINOOK_SRC" ]; then
    echo "Downloading Chinook database..."
    wget -q -O "$CHINOOK_SRC" \
        "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite" || \
    wget -q -O "$CHINOOK_SRC" \
        "https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi

if [ ! -f "$CHINOOK_SRC" ]; then
    echo "FATAL: Could not download Chinook database."
    exit 1
fi

# Create Snapshot (Original)
echo "Creating snapshot database..."
cp "$CHINOOK_SRC" "$SNAPSHOT_DB"
chmod 644 "$SNAPSHOT_DB"

# Create Production (Modified)
echo "Creating production database..."
cp "$CHINOOK_SRC" "$PROD_DB"
chmod 644 "$PROD_DB"

# Apply Modifications to Production DB using sqlite3
echo "Applying changes to production..."

# 1. Add 3 New Customers
sqlite3 "$PROD_DB" <<EOF
INSERT INTO customers (CustomerId, FirstName, LastName, Email, Country) VALUES 
(60, 'New1', 'User1', 'new1@example.com', 'USA'),
(61, 'New2', 'User2', 'new2@example.com', 'Canada'),
(62, 'New3', 'User3', 'new3@example.com', 'Mexico');
EOF

# 2. Delete 5 Invoices (IDs 10, 20, 30, 40, 50)
# Note: Chinook foreign keys might cascade or restrict, we force delete for the scenario
sqlite3 "$PROD_DB" <<EOF
PRAGMA foreign_keys = OFF;
DELETE FROM invoice_items WHERE InvoiceId IN (10, 20, 30, 40, 50);
DELETE FROM invoices WHERE InvoiceId IN (10, 20, 30, 40, 50);
EOF

# 3. Modify Prices (Increase by 1.00 for 10 tracks)
# TrackIds: 100-109
sqlite3 "$PROD_DB" <<EOF
UPDATE tracks SET UnitPrice = UnitPrice + 1.00 WHERE TrackId BETWEEN 100 AND 109;
EOF

# 4. Modify Country (Change 2 customers)
# CustomerId 5 (Czech Republic -> Germany), CustomerId 10 (Brazil -> Argentina)
sqlite3 "$PROD_DB" <<EOF
UPDATE customers SET Country = 'Germany' WHERE CustomerId = 5;
UPDATE customers SET Country = 'Argentina' WHERE CustomerId = 10;
EOF

# Verify and Record Ground Truth
echo "Verifying ground truth..."

NEW_CUSTOMERS=$(sqlite3 "$PROD_DB" "ATTACH '$SNAPSHOT_DB' AS snap; SELECT COUNT(*) FROM main.customers WHERE CustomerId NOT IN (SELECT CustomerId FROM snap.customers);")
DELETED_INVOICES=$(sqlite3 "$PROD_DB" "ATTACH '$SNAPSHOT_DB' AS snap; SELECT COUNT(*) FROM snap.invoices WHERE InvoiceId NOT IN (SELECT InvoiceId FROM main.invoices);")
PRICE_CHANGES=$(sqlite3 "$PROD_DB" "ATTACH '$SNAPSHOT_DB' AS snap; SELECT COUNT(*) FROM main.tracks t1 JOIN snap.tracks t2 ON t1.TrackId=t2.TrackId WHERE t1.UnitPrice != t2.UnitPrice;")
COUNTRY_CHANGES=$(sqlite3 "$PROD_DB" "ATTACH '$SNAPSHOT_DB' AS snap; SELECT COUNT(*) FROM main.customers c1 JOIN snap.customers c2 ON c1.CustomerId=c2.CustomerId WHERE c1.Country != c2.Country;")

echo "Ground Truth:"
echo "  New Customers: $NEW_CUSTOMERS"
echo "  Deleted Invoices: $DELETED_INVOICES"
echo "  Price Changes: $PRICE_CHANGES"
echo "  Country Changes: $COUNTRY_CHANGES"

# Save GT to JSON for export script to pick up
cat > "$GT_FILE" <<EOF
{
    "new_customers": $NEW_CUSTOMERS,
    "deleted_invoices": $DELETED_INVOICES,
    "price_changes": $PRICE_CHANGES,
    "country_changes": $COUNTRY_CHANGES
}
EOF
chmod 644 "$GT_FILE"

# Set permissions
chown ga:ga "$PROD_DB" "$SNAPSHOT_DB"

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            echo "DBeaver window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize DBeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "DBeaver" 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="