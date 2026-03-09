#!/bin/bash
set -e
echo "=== Setting up import_employees_csv task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "import_employees_csv"

# Create the CSV file with employee data
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/interns.csv << 'EOF'
Full Name,Dept,Email Address
Alice Intern,Engineering,alice.intern@example.com
Bob Intern,Engineering,bob.intern@example.com
Charlie Intern,Sales,charlie.intern@example.com
Dana Intern,Marketing,dana.intern@example.com
Evan Intern,Support,evan.intern@example.com
EOF
chown ga:ga /home/ga/Documents/interns.csv
echo "Created /home/ga/Documents/interns.csv"

# Ensure clean state: Kill running instances
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 2

# Launch Lobby Track
launch_lobbytrack

# Locate the database file to record initial state (timestamp)
# Usually in Public Documents or ProgramData
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack*.mdb" -o -name "LobbyTrack*.sdf" 2>/dev/null | head -1)

if [ -n "$DB_FILE" ]; then
    INITIAL_DB_MTIME=$(stat -c %Y "$DB_FILE")
    echo "$INITIAL_DB_MTIME" > /tmp/initial_db_mtime.txt
    echo "Located database at: $DB_FILE"
else
    echo "WARNING: Could not locate Lobby Track database file during setup."
    echo "0" > /tmp/initial_db_mtime.txt
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="