#!/bin/bash
set -e
echo "=== Setting up task: Audit Revenue Integrity ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Corrupted Data
# We copy the clean SQLite source, corrupt 3 specific records, and then generate the ODB.
echo "Generating corrupted dataset..."
cp /opt/libreoffice_base_samples/Chinook_Sqlite.sqlite /tmp/chinook_task.sqlite

# Run python script to corrupt specific records in the SQLite DB
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('/tmp/chinook_task.sqlite')
    c = conn.cursor()
    # Corrupt 3 invoices by setting Total to an incorrect value
    # Invoice 25: Real ~8.91 -> Set to 99.00
    # Invoice 50: Real ~1.98 -> Set to 5.00
    # Invoice 75: Real ~3.96 -> Set to 0.00
    c.execute('UPDATE Invoice SET Total = 99.00 WHERE InvoiceId = 25')
    c.execute('UPDATE Invoice SET Total = 5.00 WHERE InvoiceId = 50')
    c.execute('UPDATE Invoice SET Total = 0.00 WHERE InvoiceId = 75')
    conn.commit()
    print('Corrupted 3 invoice records successfully.')
    conn.close()
except Exception as e:
    print(f'Error corrupting DB: {e}')
    exit(1)
"

# 2. Convert Corrupted SQLite to ODB
# Uses the environment's conversion script
echo "Converting corrupted SQLite to ODB..."
python3 /workspace/scripts/create_chinook_odb.py \
    /tmp/chinook_task.sqlite \
    /home/ga/chinook.odb

# Set permissions
chown ga:ga /home/ga/chinook.odb
chmod 644 /home/ga/chinook.odb

# 3. Launch LibreOffice Base
source /workspace/scripts/task_utils.sh

# Kill any existing instances
kill_libreoffice

# Launch with the corrupted ODB
launch_libreoffice_base "/home/ga/chinook.odb"

# Wait for window and setup
wait_for_libreoffice_base 45
sleep 3
dismiss_dialogs
maximize_libreoffice

# Screenshot initial state
take_screenshot "/tmp/task_initial_state.png"

echo "=== Task setup complete ==="