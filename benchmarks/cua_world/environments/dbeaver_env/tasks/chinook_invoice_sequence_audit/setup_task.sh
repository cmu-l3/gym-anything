#!/bin/bash
# Setup script for chinook_invoice_sequence_audit
# Prepares a database with specific deleted records to create verifiable gaps

set -e
echo "=== Setting up Chinook Invoice Sequence Audit Task ==="

source /workspace/scripts/task_utils.sh

CHINOOK_ORIG="/home/ga/Documents/databases/chinook.db"
AUDIT_DB="/home/ga/Documents/databases/chinook_audit.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up previous run artifacts
rm -f "$EXPORT_DIR/gap_analysis.csv"
rm -f "$SCRIPTS_DIR/audit_query.sql"

# Verify source database exists
if [ ! -f "$CHINOOK_ORIG" ]; then
    echo "ERROR: Source Chinook database not found at $CHINOOK_ORIG"
    # Fallback download if missing (should be handled by env setup, but safe to have)
    wget -q -O "$CHINOOK_ORIG" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite" 2>/dev/null || true
fi

# Create the audit database from the original
echo "Creating audit database..."
cp "$CHINOOK_ORIG" "$AUDIT_DB"
chmod 666 "$AUDIT_DB"
chown ga:ga "$AUDIT_DB"

# Introduce specific gaps (GROUND TRUTH)
# We use sqlite3 to delete specific IDs
# Gaps created:
# 1. ID 10 (Single gap, length 1)
# 2. IDs 25, 26 (Range gap, length 2)
# 3. ID 50 (Single gap, length 1)
# 4. IDs 100, 101, 102, 103, 104 (Large range gap, length 5)

echo "Injecting data gaps..."
sqlite3 "$AUDIT_DB" <<EOF
DELETE FROM invoices WHERE InvoiceId = 10;
DELETE FROM invoices WHERE InvoiceId IN (25, 26);
DELETE FROM invoices WHERE InvoiceId = 50;
DELETE FROM invoices WHERE InvoiceId BETWEEN 100 AND 104;
EOF

# Save Ground Truth for verifier (Hidden from agent)
cat > /tmp/audit_ground_truth.json <<EOF
{
  "gaps": [
    {"start": 10, "end": 10, "count": 1},
    {"start": 25, "end": 26, "count": 2},
    {"start": 50, "end": 50, "count": 1},
    {"start": 100, "end": 104, "count": 5}
  ]
}
EOF
chmod 644 /tmp/audit_ground_truth.json

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "DBeaver"; then
            echo "DBeaver started"
            break
        fi
        sleep 1
    done
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Close any existing connections in UI (simulated by closing tabs if possible, 
# but hard to do programmatically. We rely on clean env state or user action).

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="