#!/bin/bash
set -euo pipefail

echo "=== Setting up Standardize Company Name task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "standardize_company_name"

# Kill any existing Lobby Track instances to release DB locks
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# ==============================================================================
# DATA PREPARATION
# ==============================================================================
# We need to ensure the database contains "Innova GmbH". 
# We'll use the sample database provided by the environment.
# We also back it up to calculate a hash/diff later if needed.

DB_DIR="/home/ga/LobbyTrack/Database"
mkdir -p "$DB_DIR"

# Locate the active database file (usually .mdb or .sdf in Documents or Program Files)
# In this env, it's often in /home/ga/LobbyTrack/Database/ or similar.
# If not found, we copy the sample.
CANDIDATE_DB=$(find /home/ga -name "*.mdb" -o -name "*.sdf" | head -n 1)

if [ -z "$CANDIDATE_DB" ]; then
    echo "No database found. Copying sample..."
    cp /workspace/data/sample.mdb "$DB_DIR/LobbyTrack.mdb" 2>/dev/null || true
    CANDIDATE_DB="$DB_DIR/LobbyTrack.mdb"
fi

echo "Using Database: $CANDIDATE_DB"
echo "$CANDIDATE_DB" > /tmp/active_db_path.txt

# Reset the DB to a known state (restoring from backup if it exists, or ensuring sample data)
# For this task, we assume the current state or sample state has "Innova GmbH".
# If we had a specific 'start state' DB, we would cp it here.
# cp /workspace/data/start_state.mdb "$CANDIDATE_DB"

# Snapshot initial state (hash)
sha256sum "$CANDIDATE_DB" > /tmp/initial_db_hash.txt

# ==============================================================================
# APPLICATION LAUNCH
# ==============================================================================
launch_lobbytrack

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target: Change 'Innova GmbH' to 'Innova Global'"