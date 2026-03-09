#!/bin/bash
set -e
echo "=== Setting up Data Quality Audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running LibreOffice
kill_libreoffice

# Restore fresh Chinook ODB
restore_chinook_odb

# Remove any previous cleanup file
rm -f /home/ga/cleanup_queries.sql

# Create the python script to inject anomalies
cat > /tmp/inject_anomalies.py << 'EOF'
import zipfile
import os
import shutil
import sys

ODB_PATH = '/home/ga/chinook.odb'

# Anomalies to inject
# 1. Duplicate Customers (IDs 60, 61, 62)
# 2. Orphan Invoices (IDs 413, 414) referencing non-existent customers
# 3. Orphan InvoiceLines (IDs 2241, 2242, 2243) referencing orphan invoices
ANOMALY_SQL = """
INSERT INTO PUBLIC."Customer" VALUES(60,'Luis','Goncalves','Embraer','Av. Brigadeiro Faria Lima, 2170','S\u00e3o Jos\u00e9 dos Campos','SP','Brazil','12227-000','+55 (12) 3923-5555','+55 (12) 3923-5566','luisg@embraer.com.br',3)
INSERT INTO PUBLIC."Customer" VALUES(61,'Frantisek','Wichterlicky','JetBrains s.r.o.','Klanova 9/506','Prague','','Czech Republic','14700','+420 2 4172 5555','+420 2 4172 5555','frantisekw@jetbrains.com',4)
INSERT INTO PUBLIC."Customer" VALUES(62,'Mark','Phillips','Telus','8210 111 ST NW','Edmonton','AB','Canada','T6G 2C7','+1 (780) 434-4554','+1 (780) 434-5565','mphilips12@shaw.ca',5)
INSERT INTO PUBLIC."Invoice" VALUES(413,99,'2025-01-15 00:00:00.0','742 Evergreen Terrace','Springfield','IL','USA','62704',5.94)
INSERT INTO PUBLIC."Invoice" VALUES(414,100,'2025-02-20 00:00:00.0','123 Fake Street','Nowhere','TX','USA','79936',8.91)
INSERT INTO PUBLIC."InvoiceLine" VALUES(2241,413,1,0.99,1)
INSERT INTO PUBLIC."InvoiceLine" VALUES(2242,413,2,0.99,1)
INSERT INTO PUBLIC."InvoiceLine" VALUES(2243,414,3,0.99,1)
"""

def main():
    if not os.path.exists(ODB_PATH):
        print(f"Error: {ODB_PATH} not found")
        sys.exit(1)

    work_dir = "/tmp/odb_work"
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    os.makedirs(work_dir)

    try:
        # Extract ODB
        with zipfile.ZipFile(ODB_PATH, 'r') as zf:
            zf.extractall(work_dir)

        # Read HSQLDB script
        script_path = os.path.join(work_dir, 'database', 'script')
        if not os.path.exists(script_path):
            print("Error: database/script not found in ODB")
            sys.exit(1)

        with open(script_path, 'r') as f:
            content = f.read()

        # Remove trailing SET WRITE_DELAY and add anomalies before it
        content = content.rstrip()
        suffix = ""
        if 'SET WRITE_DELAY' in content:
             parts = content.rsplit('SET WRITE_DELAY', 1)
             content = parts[0]
             suffix = 'SET WRITE_DELAY' + parts[1]
        
        # Append anomalies
        new_content = content + '\n' + ANOMALY_SQL.strip() + '\n' + suffix
        
        with open(script_path, 'w') as f:
            f.write(new_content)

        # Mark as modified in properties
        props_path = os.path.join(work_dir, 'database', 'properties')
        if os.path.exists(props_path):
            with open(props_path, 'r') as f:
                props = f.read()
            props = props.replace('modified=no', 'modified=yes')
            with open(props_path, 'w') as f:
                f.write(props)

        # Repackage ODB
        os.remove(ODB_PATH)
        with zipfile.ZipFile(ODB_PATH, 'w', zipfile.ZIP_DEFLATED) as zf:
            # Mimetype must be first, uncompressed
            mi = zipfile.ZipInfo('mimetype')
            mi.compress_type = zipfile.ZIP_STORED
            zf.writestr(mi, 'application/vnd.oasis.opendocument.base')

            for root, dirs, files in os.walk(work_dir):
                for fname in sorted(files):
                    fpath = os.path.join(root, fname)
                    arcname = os.path.relpath(fpath, work_dir)
                    if arcname == 'mimetype':
                        continue
                    zf.write(fpath, arcname)

        print("Anomalies injected successfully.")

    except Exception as e:
        print(f"Error injecting anomalies: {e}")
        sys.exit(1)
    finally:
        if os.path.exists(work_dir):
            shutil.rmtree(work_dir)

if __name__ == '__main__':
    main()
EOF

# Run injection script
echo "Injecting data quality anomalies..."
python3 /tmp/inject_anomalies.py

# Set permissions
chown ga:ga /home/ga/chinook.odb
chmod 644 /home/ga/chinook.odb

# Verify injection
ODB_SIZE=$(stat -c%s /home/ga/chinook.odb)
echo "Modified chinook.odb size: ${ODB_SIZE} bytes"

# Launch LibreOffice Base
launch_libreoffice_base /home/ga/chinook.odb
wait_for_libreoffice_base 45

sleep 3
dismiss_dialogs
sleep 2
maximize_libreoffice
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Data Quality Audit task setup complete ==="