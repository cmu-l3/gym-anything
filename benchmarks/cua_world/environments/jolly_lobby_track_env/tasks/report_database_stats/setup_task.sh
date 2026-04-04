#!/bin/bash
set -euo pipefail

echo "=== Setting up report_database_stats task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "report_database_stats"

# ------------------------------------------------------------------
# CALCULATE GROUND TRUTH
# ------------------------------------------------------------------
# We derive the expected counts from the source CSV files provided in the environment.
# We assume the application database is synced with these files.
# We subtract 1 for the header row.

VISITOR_CSV="/workspace/data/visitor_records.csv"
HOST_CSV="/workspace/data/employee_hosts.csv"

if [ -f "$VISITOR_CSV" ]; then
    # Count lines, subtract 1 for header
    RAW_V_COUNT=$(wc -l < "$VISITOR_CSV")
    VISITOR_COUNT=$((RAW_V_COUNT - 1))
else
    echo "WARNING: Visitor CSV not found, defaulting to 0"
    VISITOR_COUNT=0
fi

if [ -f "$HOST_CSV" ]; then
    # Count lines, subtract 1 for header
    RAW_H_COUNT=$(wc -l < "$HOST_CSV")
    HOST_COUNT=$((RAW_H_COUNT - 1))
else
    echo "WARNING: Host CSV not found, defaulting to 0"
    HOST_COUNT=0
fi

# Save ground truth to a JSON file (hidden from agent, used by verifier)
# We add a small tolerance notes in the JSON for the verifier
cat > /tmp/ground_truth_stats.json << EOF
{
    "expected_visitors": $VISITOR_COUNT,
    "expected_hosts": $HOST_COUNT,
    "tolerance": 5,
    "visitor_source": "$VISITOR_CSV",
    "host_source": "$HOST_CSV"
}
EOF

echo "Ground Truth Calculated:"
cat /tmp/ground_truth_stats.json

# ------------------------------------------------------------------
# APPLICATION SETUP
# ------------------------------------------------------------------

# Ensure clean state
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch Lobby Track
launch_lobbytrack

# Ensure data directory permissions (just in case agent needs to read something, though unlikely)
mkdir -p /home/ga/LobbyTrack/data
cp /workspace/data/*.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/LobbyTrack/

echo "=== report_database_stats task setup complete ==="