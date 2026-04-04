#!/bin/bash
set -euo pipefail

echo "=== Setting up bulk_checkin_expected_group task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "bulk_checkin_expected_group"

# Kill any existing Lobby Track instance to ensure clean state
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Restore initial database state (simulated for this environment)
# In a real scenario, we would copy a specific MDB file here.
# Assuming the default environment data contains the 'Apex Financial' pre-registrations.
# If not, we would import them here.
echo "Ensuring database is in clean state..."
if [ -f "/home/ga/LobbyTrack/data/clean_db.mdb" ]; then
    cp "/home/ga/LobbyTrack/data/clean_db.mdb" "/home/ga/LobbyTrack/data/LobbyTrack.mdb"
fi

# Create a context note for the agent
cat > /home/ga/Desktop/reception_note.txt << 'EOF'
URGENT:
The auditors from Apex Financial have arrived.
Please find their pre-registered records and check them in immediately.
Names:
- Elena Fisher
- Victor Sullivan
- Chloe Frazer

Do NOT create new records. They are already in the system as "Expected".
EOF
chmod 666 /home/ga/Desktop/reception_note.txt

# Launch Lobby Track
launch_lobbytrack

# Record initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="