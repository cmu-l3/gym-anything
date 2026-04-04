#!/bin/bash
# Setup script for chinook_resurrected_customer_analysis
# Ensures DB exists and injects specific transaction patterns for deterministic verification

set -e
echo "=== Setting up Resurrected Customer Analysis Task ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# 1. Ensure Chinook database exists (using the environment's default setup logic if missing)
if [ ! -f "$DB_PATH" ]; then
    echo "Restoring Chinook database..."
    if [ -f "/workspace/data/chinook.db" ]; then
        cp "/workspace/data/chinook.db" "$DB_PATH"
    else
        # Fallback download
        wget -q -O "$DB_PATH" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    fi
fi
chmod 666 "$DB_PATH"

# 2. SEED DATA: Inject specific patterns to ensure ground truth is robust
# We need to guarantee:
# - Customer A: Active 2009, Dormant 2010, Active 2011 (The Target)
# - Customer B: Active 2009, Active 2010, Active 2011 (False Positive - no dormancy)
# - Customer C: Active 2009, Dormant 2010, Dormant 2011 (False Positive - didn't return)
# - Customer D: Dormant 2009, Dormant 2010, Active 2011 (False Positive - new customer, not resurrected)

echo "Seeding database with specific transaction patterns..."
sqlite3 "$DB_PATH" <<EOF
BEGIN TRANSACTION;

-- Pick specific IDs to manipulate (using IDs usually present in Chinook)
-- ID 1: TARGET (Resurrected)
DELETE FROM invoices WHERE CustomerId = 1;
INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, BillingPostalCode, Total) VALUES
(1001, 1, '2009-02-15 00:00:00', 'Address', 'City', 'Country', '0000', 10.00),
(1002, 1, '2011-03-20 00:00:00', 'Address', 'City', 'Country', '0000', 25.00);

-- ID 2: FALSE POSITIVE (Continuous - bought in 2010)
DELETE FROM invoices WHERE CustomerId = 2;
INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, BillingPostalCode, Total) VALUES
(2001, 2, '2009-05-10 00:00:00', 'Address', 'City', 'Country', '0000', 5.00),
(2002, 2, '2010-06-15 00:00:00', 'Address', 'City', 'Country', '0000', 5.00),
(2003, 2, '2011-08-20 00:00:00', 'Address', 'City', 'Country', '0000', 5.00);

-- ID 3: FALSE POSITIVE (Churned - bought 2009, nothing since)
DELETE FROM invoices WHERE CustomerId = 3;
INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, BillingPostalCode, Total) VALUES
(3001, 3, '2009-01-01 00:00:00', 'Address', 'City', 'Country', '0000', 8.00);

-- ID 4: FALSE POSITIVE (New - bought 2011, nothing before)
DELETE FROM invoices WHERE CustomerId = 4;
INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, BillingPostalCode, Total) VALUES
(4001, 4, '2011-12-01 00:00:00', 'Address', 'City', 'Country', '0000', 15.00);

-- ID 5: TARGET (Resurrected - verify sum logic)
DELETE FROM invoices WHERE CustomerId = 5;
INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, BillingPostalCode, Total) VALUES
(5001, 5, '2009-11-11 00:00:00', 'Address', 'City', 'Country', '0000', 10.00),
(5002, 5, '2011-01-01 00:00:00', 'Address', 'City', 'Country', '0000', 50.00),
(5003, 5, '2011-02-01 00:00:00', 'Address', 'City', 'Country', '0000', 50.00);
-- Customer 5 2011 Spend should be 100.00

COMMIT;
EOF

echo "Database seeding complete."

# 3. Calculate Ground Truth immediately
# We do this in setup so we have a reference that doesn't depend on what the agent does to the DB
# (though the agent shouldn't modify data for this task, better safe than sorry)
echo "Calculating ground truth..."
sqlite3 -header -csv "$DB_PATH" "
WITH Active2009 AS (
    SELECT DISTINCT CustomerId FROM invoices WHERE strftime('%Y', InvoiceDate) = '2009'
),
Active2010 AS (
    SELECT DISTINCT CustomerId FROM invoices WHERE strftime('%Y', InvoiceDate) = '2010'
),
Active2011 AS (
    SELECT DISTINCT CustomerId FROM invoices WHERE strftime('%Y', InvoiceDate) = '2011'
),
Resurrected AS (
    SELECT CustomerId FROM Active2009
    EXCEPT
    SELECT CustomerId FROM Active2010
    INTERSECT
    SELECT CustomerId FROM Active2011
)
SELECT
    c.CustomerId,
    c.FirstName,
    c.LastName,
    SUM(i.Total) as ReturnSpend2011
FROM Resurrected r
JOIN customers c ON r.CustomerId = c.CustomerId
JOIN invoices i ON r.CustomerId = i.CustomerId
WHERE strftime('%Y', i.InvoiceDate) = '2011'
GROUP BY c.CustomerId
ORDER BY ReturnSpend2011 DESC;
" > /tmp/ground_truth.csv

echo "Ground Truth Content:"
cat /tmp/ground_truth.csv

# 4. Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
fi

# Wait for window and maximize
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "DBeaver"; then
        echo "DBeaver window found."
        DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# Timestamp
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="