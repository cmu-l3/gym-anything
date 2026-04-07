#!/bin/bash
# Setup script for chinook_revenue_reconciliation task
# Creates a Chinook database copy with injected anomalies:
#   1. A general_ledger table with correct pre-error monthly revenue
#   2. An import_log table showing a failed-then-retried batch import
#   3. 18 duplicate invoice_items (simulating the double import)
#   4. Recalculated invoice totals that include the duplicates
#   5. A compensating credit memo (negative invoice) assigned to the wrong customer

set -e
echo "=== Setting up Chinook Revenue Reconciliation Task ==="

source /workspace/scripts/task_utils.sh

# Paths
ORIGINAL_DB="/home/ga/Documents/databases/chinook.db"
LEDGER_DB="/home/ga/Documents/databases/chinook_ledger.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPT_DIR="/home/ga/Documents/scripts"

mkdir -p "$EXPORT_DIR" "$SCRIPT_DIR" "$(dirname "$LEDGER_DB")"
chown -R ga:ga /home/ga/Documents

# Delete stale outputs BEFORE recording timestamp
rm -f "$LEDGER_DB"
rm -f "$EXPORT_DIR/correction_report.csv"
rm -f "$SCRIPT_DIR/reconciliation.sql"
rm -f /tmp/reconciliation_ground_truth.json
rm -f /tmp/reconciliation_result.json
rm -f /tmp/task_result.json

# Record task start time
date +%s > /tmp/task_start_time

# Verify source database exists
if [ ! -f "$ORIGINAL_DB" ]; then
    echo "ERROR: Source Chinook database not found at $ORIGINAL_DB"
    exit 1
fi

# Create fresh copy
echo "Creating ledger database copy..."
cp "$ORIGINAL_DB" "$LEDGER_DB"
chown ga:ga "$LEDGER_DB"

# Verify the copy
TABLE_COUNT=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table'" 2>/dev/null || echo 0)
if [ "$TABLE_COUNT" -lt 5 ]; then
    echo "ERROR: Database copy appears incomplete ($TABLE_COUNT tables)"
    exit 1
fi

echo "Injecting anomalies into ledger database..."

# Use Python for the complex multi-step setup to ensure determinism
python3 << 'PYEOF'
import sqlite3
import json

db = sqlite3.connect('/home/ga/Documents/databases/chinook_ledger.db')
cur = db.cursor()

# ============================================================
# Step 1: Create general_ledger with CORRECT revenue (before any corruption)
# ============================================================
cur.execute("""
    CREATE TABLE general_ledger (
        LedgerId INTEGER PRIMARY KEY AUTOINCREMENT,
        YearMonth TEXT NOT NULL UNIQUE,
        Revenue REAL NOT NULL,
        InvoiceCount INTEGER NOT NULL
    )
""")
cur.execute("""
    INSERT INTO general_ledger (YearMonth, Revenue, InvoiceCount)
    SELECT strftime('%Y-%m', InvoiceDate) AS ym,
           ROUND(SUM(Total), 2),
           COUNT(*)
    FROM invoices
    GROUP BY ym
    ORDER BY ym
""")
db.commit()
print("General ledger created with correct monthly revenue.")

# ============================================================
# Step 2: Create import_log table (breadcrumbs for investigation)
# ============================================================
cur.execute("""
    CREATE TABLE import_log (
        LogId INTEGER PRIMARY KEY,
        ImportTimestamp TEXT,
        BatchName TEXT,
        RecordCount INTEGER,
        TargetTable TEXT,
        Status TEXT,
        Notes TEXT
    )
""")
cur.execute("""
    INSERT INTO import_log VALUES
        (1, '2025-01-15 09:30:00', 'catalog_refresh_2013q2', 245,
         'tracks', 'COMPLETED', 'Routine catalog metadata update'),
        (2, '2025-02-01 14:15:00', 'q4_invoice_correction', NULL,
         'invoice_items', 'FAILED', 'Connection timeout during batch insert'),
        (3, '2025-02-01 14:45:00', 'q4_invoice_correction_retry', NULL,
         'invoice_items', 'COMPLETED',
         'Re-run of failed batch 2 -- verify no duplicates were created')
""")
db.commit()
print("Import log created.")

# ============================================================
# Step 3: Record original state before corruption
# ============================================================
cur.execute("SELECT MAX(InvoiceLineId) FROM invoice_items")
original_max_line_id = cur.fetchone()[0]

cur.execute("SELECT MAX(InvoiceId) FROM invoices")
original_max_invoice_id = cur.fetchone()[0]

cur.execute("SELECT COUNT(*) FROM invoice_items")
original_item_count = cur.fetchone()[0]

print(f"Original state: {original_item_count} invoice_items, "
      f"max InvoiceLineId={original_max_line_id}, "
      f"max InvoiceId={original_max_invoice_id}")

# ============================================================
# Step 4: Inject 18 duplicate invoice_items from Q4 2013
#         (6 per month to spread across Oct, Nov, Dec)
# ============================================================
for month_start, month_end in [
    ('2013-10-01', '2013-11-01'),
    ('2013-11-01', '2013-12-01'),
    ('2013-12-01', '2014-01-01'),
]:
    cur.execute(f"""
        INSERT INTO invoice_items (InvoiceId, TrackId, UnitPrice, Quantity)
        SELECT ii.InvoiceId, ii.TrackId, ii.UnitPrice, ii.Quantity
        FROM invoice_items ii
        JOIN invoices i ON ii.InvoiceId = i.InvoiceId
        WHERE i.InvoiceDate >= '{month_start}' AND i.InvoiceDate < '{month_end}'
          AND ii.InvoiceLineId <= {original_max_line_id}
        ORDER BY ii.InvoiceLineId
        LIMIT 6
    """)
db.commit()

# Get the duplicate IDs
cur.execute(f"""
    SELECT InvoiceLineId FROM invoice_items
    WHERE InvoiceLineId > {original_max_line_id}
    ORDER BY InvoiceLineId
""")
duplicate_ids = [row[0] for row in cur.fetchall()]
print(f"Injected {len(duplicate_ids)} duplicate invoice_items: IDs {duplicate_ids}")

# Update import_log with actual counts
cur.execute(f"UPDATE import_log SET RecordCount = {len(duplicate_ids)} WHERE LogId IN (2, 3)")
db.commit()

# Get affected invoice IDs
cur.execute(f"""
    SELECT DISTINCT ii.InvoiceId
    FROM invoice_items ii
    WHERE ii.InvoiceLineId > {original_max_line_id}
    ORDER BY ii.InvoiceId
""")
affected_invoice_ids = [row[0] for row in cur.fetchall()]
print(f"Affected invoices: {affected_invoice_ids}")

# ============================================================
# Step 5: Recalculate affected invoice Totals (simulates automated fix)
# ============================================================
# Store original totals before recalculation
original_totals = {}
for inv_id in affected_invoice_ids:
    cur.execute("SELECT Total FROM invoices WHERE InvoiceId = ?", (inv_id,))
    original_totals[inv_id] = cur.fetchone()[0]

for inv_id in affected_invoice_ids:
    cur.execute("""
        UPDATE invoices SET Total = (
            SELECT ROUND(SUM(UnitPrice * Quantity), 2)
            FROM invoice_items WHERE InvoiceId = ?
        ) WHERE InvoiceId = ?
    """, (inv_id, inv_id))
db.commit()
print("Recalculated Q4 2013 invoice totals (now include duplicates).")

# ============================================================
# Step 6: Find customer with NO Q4 2013 invoices for credit memo
# ============================================================
cur.execute("""
    SELECT c.CustomerId
    FROM customers c
    WHERE c.CustomerId NOT IN (
        SELECT DISTINCT CustomerId FROM invoices
        WHERE InvoiceDate >= '2013-10-01' AND InvoiceDate < '2014-01-01'
    )
    ORDER BY c.CustomerId
    LIMIT 1
""")
credit_memo_customer = cur.fetchone()[0]
print(f"Credit memo customer (no Q4 2013 invoices): {credit_memo_customer}")

# ============================================================
# Step 7: Calculate November duplicate total for credit memo
# ============================================================
cur.execute(f"""
    SELECT ROUND(SUM(ii.UnitPrice * ii.Quantity), 2)
    FROM invoice_items ii
    JOIN invoices i ON ii.InvoiceId = i.InvoiceId
    WHERE ii.InvoiceLineId > {original_max_line_id}
      AND i.InvoiceDate >= '2013-11-01' AND i.InvoiceDate < '2013-12-01'
""")
nov_dup_total = cur.fetchone()[0]
if nov_dup_total is None:
    nov_dup_total = 0.0
print(f"November duplicate total: ${nov_dup_total}")

# ============================================================
# Step 8: Insert compensating credit memo (negative invoice)
# ============================================================
credit_memo_id = None
credit_memo_total = 0.0

if nov_dup_total > 0:
    cur.execute("""
        SELECT Address, City, State, Country, PostalCode
        FROM customers WHERE CustomerId = ?
    """, (credit_memo_customer,))
    cust = cur.fetchone()

    credit_memo_total = round(-1.0 * nov_dup_total, 2)
    cur.execute("""
        INSERT INTO invoices (CustomerId, InvoiceDate, BillingAddress, BillingCity,
            BillingState, BillingCountry, BillingPostalCode, Total)
        VALUES (?, '2013-11-28', ?, ?, ?, ?, ?, ?)
    """, (credit_memo_customer, cust[0], cust[1], cust[2], cust[3], cust[4],
          credit_memo_total))
    db.commit()

    cur.execute("SELECT last_insert_rowid()")
    credit_memo_id = cur.fetchone()[0]
    print(f"Credit memo inserted: InvoiceId={credit_memo_id}, "
          f"CustomerId={credit_memo_customer}, Total=${credit_memo_total}")
else:
    print("No November duplicates found; no credit memo inserted.")

# ============================================================
# Step 9: Collect ground truth
# ============================================================
cur.execute("SELECT YearMonth, Revenue FROM general_ledger ORDER BY YearMonth")
gl_data = {row[0]: row[1] for row in cur.fetchall()}

ground_truth = {
    "original_invoice_item_count": original_item_count,
    "original_max_invoice_line_id": original_max_line_id,
    "original_max_invoice_id": original_max_invoice_id,
    "duplicate_invoice_line_ids": duplicate_ids,
    "duplicate_count": len(duplicate_ids),
    "affected_invoice_ids": affected_invoice_ids,
    "original_invoice_totals": original_totals,
    "credit_memo_invoice_id": credit_memo_id,
    "credit_memo_customer_id": credit_memo_customer,
    "credit_memo_total": credit_memo_total,
    "discrepant_months": ["2013-10", "2013-11", "2013-12"],
    "correct_monthly_revenue": gl_data
}

with open('/tmp/reconciliation_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print("\nGround truth saved to /tmp/reconciliation_ground_truth.json")
print(f"  Duplicates: {len(duplicate_ids)} items")
print(f"  Affected invoices: {len(affected_invoice_ids)}")
print(f"  Credit memo: InvoiceId={credit_memo_id}, Customer={credit_memo_customer}")

db.close()
PYEOF

echo "Database anomalies injected successfully."

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null 2>&1; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    for i in $(seq 1 60); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
            echo "DBeaver window detected."
            break
        fi
        sleep 1
    done
fi

focus_dbeaver || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Revenue Reconciliation Task Setup Complete ==="
