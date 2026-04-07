#!/bin/bash
# Setup script for sakila_payment_reconciliation_audit task

echo "=== Setting up Sakila Payment Reconciliation Audit Task ==="

source /workspace/scripts/task_utils.sh

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi
focus_workbench

# ----- Clean up previous state BEFORE recording timestamp -----
echo "Cleaning up previous state..."

# Remove export files
rm -f /home/ga/Documents/exports/reconciliation_report.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/reconciliation_summary.csv 2>/dev/null || true
rm -f /home/ga/Documents/imports/processor_transactions.csv 2>/dev/null || true

# Drop previous DB objects
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TABLE IF EXISTS processor_transactions;
    DROP TABLE IF EXISTS audit_corrections;
    DROP TABLE IF EXISTS reconciliation_summary;
    DROP VIEW IF EXISTS v_payment_reconciliation;
    DROP PROCEDURE IF EXISTS sp_apply_corrections;
" 2>/dev/null || true

# Remove previous ground truth
rm -f /tmp/reconciliation_ground_truth.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# ----- Record task start timestamp -----
date +%s > /tmp/task_start_timestamp

# Create directories
mkdir -p /home/ga/Documents/imports
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# ----- Generate processor CSV via Python3 -----
echo "Generating payment processor CSV..."

python3 << 'PYEOF'
import pymysql
import csv
import json
import hashlib
import random
from datetime import timedelta

random.seed(42)  # Deterministic

conn = pymysql.connect(
    host='localhost', user='root',
    password='GymAnything#2024', database='sakila'
)
cur = conn.cursor(pymysql.cursors.DictCursor)

# Get all July 2005 payments with customer emails
cur.execute("""
    SELECT p.payment_id, p.customer_id, c.email, p.amount,
           DATE(p.payment_date) as pay_date, p.staff_id, p.rental_id
    FROM payment p
    JOIN customer c ON p.customer_id = c.customer_id
    WHERE p.payment_date >= '2005-07-01'
      AND p.payment_date < '2005-08-01'
    ORDER BY p.payment_id
""")
payments = list(cur.fetchall())
total = len(payments)

# Assign categories deterministically based on position in sorted list
internal_only_ids = set()
date_mismatch_ids = set()
amount_mismatch_ids = set()
duplicate_ids = set()

for i, p in enumerate(payments):
    pid = p['payment_id']
    if i < 40:
        internal_only_ids.add(pid)
    elif i < 90:
        date_mismatch_ids.add(pid)
    elif i < 125:
        amount_mismatch_ids.add(pid)
    elif i < 145:
        duplicate_ids.add(pid)
    # Remaining → MATCHED

# Notes templates — some contain commas (will be properly quoted by csv.writer)
notes_pool = [
    "Payment processed",
    "Standard transaction",
    "Cleared batch #{}".format(random.randint(1000, 9999)),
    "Auto-debit ref SAK",
    "Recurring payment",
    "Payment processed, confirmation sent",
    "Cleared, pending review",
    "Standard, monthly billing cycle",
    "Transaction complete, no issues",
    "Processed via gateway, settled",
]

# Track amount deltas for ground truth
amount_deltas = {}

csv_rows = []
for p in payments:
    pid = p['payment_id']
    if pid in internal_only_ids:
        continue  # Omit from CSV → INTERNAL_ONLY

    txn_hash = hashlib.md5(str(pid).encode()).hexdigest()[:8].upper()
    txn_id = "TXN-" + txn_hash
    merchant_ref = "SAK-{}".format(pid)
    email = p['email'] if p['email'] else ""
    amount = float(p['amount'])
    txn_date = p['pay_date']
    status = "completed"
    note = notes_pool[pid % len(notes_pool)]

    # DATE_MISMATCH: shift date by 1 or 2 days
    if pid in date_mismatch_ids:
        shift = 1 if pid % 2 == 0 else 2
        txn_date = txn_date + timedelta(days=shift)

    # AMOUNT_MISMATCH: modify amount by $0.05 to $0.49
    if pid in amount_mismatch_ids:
        delta = round(0.05 + (pid % 45) * 0.01, 2)
        amount_deltas[pid] = delta
        amount = round(amount + delta, 2)

    # Data quality issues (deterministic by pid):
    # ~5% have $ prefix in amount
    if pid % 20 == 0:
        amount_str = "${:.2f}".format(amount)
    else:
        amount_str = "{:.2f}".format(amount)

    # ~3% have MM/DD/YYYY date format
    if pid % 33 == 0:
        date_str = txn_date.strftime("%m/%d/%Y")
    else:
        date_str = str(txn_date)

    # ~2% have empty email
    if pid % 50 == 0:
        email = ""

    row = [txn_id, merchant_ref, email, amount_str, date_str, status, note]
    csv_rows.append(row)

    # DUPLICATE_EXTERNAL: add a second copy with same txn_id
    if pid in duplicate_ids:
        dup_note = "Duplicate, reprocessed"
        dup_row = [txn_id, merchant_ref, email, amount_str, date_str, status, dup_note]
        csv_rows.append(dup_row)

# EXTERNAL_ONLY: 30 synthetic records not matching any Sakila payment
external_only_txns = []
for i in range(30):
    txn_id = "TXN-EXT{:04d}".format(i)
    # Some have emails that exist in sakila (but amount/date won't match closely)
    # Others have fake emails
    if i < 15:
        email = "refund_{}@example.com".format(i)
    else:
        email = ""
    amount = round(random.uniform(0.99, 9.99), 2)
    day = random.randint(1, 28)
    row = [
        txn_id,
        "ADJ-{}".format(i),
        email,
        "{:.2f}".format(amount),
        "2005-07-{:02d}".format(day),
        "refund",
        "Adjustment, processor initiated"
    ]
    csv_rows.append(row)
    external_only_txns.append(txn_id)

# Shuffle rows so categories aren't grouped
random.shuffle(csv_rows)

# Write RFC 4180 compliant CSV (csv.writer handles quoting fields with commas)
csv_path = '/home/ga/Documents/imports/processor_transactions.csv'
with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(['txn_id', 'merchant_ref', 'cust_email', 'amount',
                     'txn_date', 'status', 'notes'])
    writer.writerows(csv_rows)

# Count categories
matched_count = total - len(internal_only_ids) - len(date_mismatch_ids) \
                - len(amount_mismatch_ids)

# Save ground truth for verification
ground_truth = {
    "total_july_payments": total,
    "csv_data_rows": len(csv_rows),
    "internal_only_count": len(internal_only_ids),
    "date_mismatch_count": len(date_mismatch_ids),
    "amount_mismatch_count": len(amount_mismatch_ids),
    "duplicate_count": len(duplicate_ids),
    "external_only_count": 30,
    "matched_count": matched_count,
    "internal_only_pids": sorted(internal_only_ids),
    "date_mismatch_pids": sorted(date_mismatch_ids),
    "amount_mismatch_pids": sorted(amount_mismatch_ids),
    "duplicate_pids": sorted(duplicate_ids),
    "external_only_txns": external_only_txns,
    "amount_deltas": {str(k): v for k, v in amount_deltas.items()}
}
with open('/tmp/reconciliation_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, default=str)

print("Generated {} CSV rows from {} July 2005 payments".format(
    len(csv_rows), total))
print("Categories: {} INTERNAL_ONLY, {} DATE_MISMATCH, {} AMOUNT_MISMATCH, "
      "{} DUPLICATE, {} EXTERNAL_ONLY, {} MATCHED".format(
    len(internal_only_ids), len(date_mismatch_ids),
    len(amount_mismatch_ids), len(duplicate_ids),
    30, matched_count))

conn.close()
PYEOF

chown ga:ga /home/ga/Documents/imports/processor_transactions.csv

echo "Ground truth saved to /tmp/reconciliation_ground_truth.json"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Payment Reconciliation Audit Setup Complete ==="
