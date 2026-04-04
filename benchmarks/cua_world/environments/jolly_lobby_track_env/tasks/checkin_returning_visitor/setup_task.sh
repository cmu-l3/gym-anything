#!/bin/bash
set -euo pipefail

echo "=== Setting up checkin_returning_visitor task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "checkin_returning_visitor"

# Kill any existing Lobby Track instance to ensure clean start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# ==============================================================================
# Prepare the Historical Visitor CSV
# ==============================================================================
echo "Creating historical visitor CSV..."
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/historical_visitors.csv << EOF
First Name,Last Name,Company,Email,Phone,Visitor Group,Host Name,Purpose
David,Miller,Acme Corp,david.m@acme.com,555-0101,Visitor,James Wilson,Meeting
Sarah,Chen,Deloitte,schen@deloitte.com,555-0102,Visitor,David Park,Meeting
Jessica,Wong,Consulting Partners,j.wong@cp.com,555-0103,Visitor,Emily Davis,Vendor
EOF

chown ga:ga /home/ga/Documents/historical_visitors.csv
chmod 644 /home/ga/Documents/historical_visitors.csv

# ==============================================================================
# Launch Application
# ==============================================================================
echo "Launching Lobby Track..."
launch_lobbytrack

# Record the initial state of the database file (if it exists)
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack.mdb" 2>/dev/null | head -1)
if [ -f "$DB_FILE" ]; then
    stat -c %Y "$DB_FILE" > /tmp/initial_db_mtime.txt
    stat -c %s "$DB_FILE" > /tmp/initial_db_size.txt
    echo "Initial DB found: $DB_FILE"
else
    echo "0" > /tmp/initial_db_mtime.txt
    echo "0" > /tmp/initial_db_size.txt
    echo "No initial DB found (will likely be created on first run)"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Import historical_visitors.csv, then check in Sarah Chen (Deloitte) as Contractor for host Michael Torres."