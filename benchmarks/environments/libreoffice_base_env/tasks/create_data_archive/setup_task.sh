#!/bin/bash
set -e
echo "=== Setting up create_data_archive task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Compute Ground Truth ---
# We compute the expected row counts from the source SQLite database
# so the verifier knows exactly what to look for.
echo "Computing ground truth..."
python3 -c "
import sqlite3
import json

conn = sqlite3.connect('/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite')
c = conn.cursor()

# 1. Total original counts
c.execute('SELECT COUNT(*) FROM Invoice')
total_invoices = c.fetchone()[0]

c.execute('SELECT COUNT(*) FROM InvoiceLine')
total_lines = c.fetchone()[0]

# 2. Archive counts (2009)
c.execute(\"SELECT COUNT(*) FROM Invoice WHERE InvoiceDate >= '2009-01-01' AND InvoiceDate < '2010-01-01'\")
archive_invoices = c.fetchone()[0]

c.execute(\"\"\"
    SELECT COUNT(*) FROM InvoiceLine 
    WHERE InvoiceId IN (
        SELECT InvoiceId FROM Invoice 
        WHERE InvoiceDate >= '2009-01-01' AND InvoiceDate < '2010-01-01'
    )
\"\"\")
archive_lines = c.fetchone()[0]

# 3. Expected remaining counts
remaining_invoices = total_invoices - archive_invoices
remaining_lines = total_lines - archive_lines

ground_truth = {
    'total_invoices': total_invoices,
    'total_lines': total_lines,
    'archive_invoices': archive_invoices,
    'archive_lines': archive_lines,
    'remaining_invoices': remaining_invoices,
    'remaining_lines': remaining_lines
}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

print(f'Ground Truth calculated: {json.dumps(ground_truth)}')
conn.close()
"

# Set permissions for ground truth so agent cannot modify it easily (root owned)
chmod 644 /tmp/ground_truth.json

# --- Setup LibreOffice Base ---
# Kills existing instances, restores fresh ODB, launches app, handles dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial checksum of the ODB file to detect modification later
md5sum /home/ga/chinook.odb | awk '{print $1}' > /tmp/initial_odb_checksum.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="