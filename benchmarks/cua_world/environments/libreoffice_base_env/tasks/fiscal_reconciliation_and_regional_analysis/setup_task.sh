#!/bin/bash
set -e
echo "=== Setting up task: Fiscal Reconciliation and Regional Analysis ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------
# 1. Prepare Corrupted Data
#    Copy the clean SQLite source, corrupt 10 invoice totals, compute
#    ground truth (correct totals + region assignments), then regenerate
#    the ODB from the corrupted SQLite.
# -----------------------------------------------------------------------
echo "Generating corrupted dataset and ground truth..."
cp /opt/libreoffice_base_samples/Chinook_Sqlite.sqlite /tmp/chinook_task.sqlite

python3 -c "
import sqlite3
import json

conn = sqlite3.connect('/tmp/chinook_task.sqlite')
c = conn.cursor()

# 10 invoices to corrupt, with their fake totals
corruptions = {
    5:   138.60,
    15:    0.00,
    50:  105.94,
    75:   39.60,
    100:   0.01,
    150:  99.99,
    200:  50.00,
    250:   0.00,
    300:  25.00,
    375: 500.00,
}

# Region mapping (country -> RegionId)
region_map = {
    'USA': 1, 'Canada': 1,
    'Germany': 2, 'France': 2, 'United Kingdom': 2, 'Czech Republic': 2,
    'Portugal': 2, 'Austria': 2, 'Belgium': 2, 'Denmark': 2, 'Finland': 2,
    'Hungary': 2, 'Ireland': 2, 'Italy': 2, 'Netherlands': 2, 'Norway': 2,
    'Poland': 2, 'Spain': 2, 'Sweden': 2,
    'Brazil': 3, 'Argentina': 3, 'Chile': 3,
    'Australia': 4, 'India': 4,
}

ground_truth = {
    'discrepancies': [],
    'region_spot_checks': [],
    'region_counts': {},
}

# Compute correct totals, then corrupt
for inv_id, fake_total in corruptions.items():
    c.execute(
        'SELECT SUM(UnitPrice * Quantity) FROM InvoiceLine WHERE InvoiceId = ?',
        (inv_id,)
    )
    correct = round(c.fetchone()[0], 2)
    ground_truth['discrepancies'].append({
        'invoice_id': inv_id,
        'correct_total': correct,
        'corrupted_total': fake_total,
    })
    c.execute('UPDATE Invoice SET Total = ? WHERE InvoiceId = ?', (fake_total, inv_id))

conn.commit()
print(f'Corrupted {len(corruptions)} invoice records.')

# Compute region spot checks and counts from billing countries
c.execute('SELECT InvoiceId, BillingCountry FROM Invoice')
region_counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
spot_checks = []
for inv_id, country in c.fetchall():
    rid = region_map.get(country, 5)
    region_counts[rid] += 1
    # Pick a handful of spot checks (first seen per region)
    if len([s for s in spot_checks if s['expected_region'] == rid]) < 2:
        spot_checks.append({
            'invoice_id': inv_id,
            'billing_country': country,
            'expected_region': rid,
        })

ground_truth['region_spot_checks'] = spot_checks
ground_truth['region_counts'] = region_counts

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f'Ground truth written: {len(ground_truth[\"discrepancies\"])} discrepancies, '
      f'{len(spot_checks)} spot checks')
conn.close()
"

chmod 644 /tmp/ground_truth.json

# -----------------------------------------------------------------------
# 2. Convert Corrupted SQLite to ODB
# -----------------------------------------------------------------------
echo "Converting corrupted SQLite to ODB..."
python3 /workspace/scripts/create_chinook_odb.py \
    /tmp/chinook_task.sqlite \
    /home/ga/chinook.odb

chown ga:ga /home/ga/chinook.odb
chmod 644 /home/ga/chinook.odb

# Record initial MD5 checksum for modification detection
md5sum /home/ga/chinook.odb | awk '{print $1}' > /tmp/initial_odb_checksum.txt

# -----------------------------------------------------------------------
# 3. Launch LibreOffice Base
# -----------------------------------------------------------------------
source /workspace/scripts/task_utils.sh

kill_libreoffice
launch_libreoffice_base "/home/ga/chinook.odb"
wait_for_libreoffice_base 45
sleep 3
dismiss_dialogs
maximize_libreoffice

take_screenshot "/tmp/task_initial_state.png"

echo "=== Task setup complete ==="
echo "Chinook database loaded with 10 corrupted invoice totals."
echo "Agent must: create InvoiceHealthCheck view, CorrectionBatch table,"
echo "fix invoice totals, create RegionMapping, assign regions,"
echo "create RegionalRevenueBreakdown query, create CorrectionAuditTrail view."
