#!/bin/bash
echo "=== Setting up register_health_professional task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure PostgreSQL is running
wait_for_postgres 60

# Ensure GNU Health server is active
systemctl is-active gnuhealth || systemctl start gnuhealth
sleep 5

# Remove any existing test data from previous attempts to ensure a clean state
echo "Cleaning up any pre-existing records for Maria Santos..."
# Fetch potential party IDs
PARTY_IDS=$(gnuhealth_db_query "SELECT id FROM party_party WHERE name ILIKE '%Maria%' AND lastname ILIKE '%Santos%'" 2>/dev/null || true)
if [ -n "$PARTY_IDS" ]; then
    for pid in $PARTY_IDS; do
        gnuhealth_db_query "DELETE FROM gnuhealth_healthprofessional WHERE name = $pid" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM gnuhealth_healthprofessional WHERE party = $pid" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM party_party WHERE id = $pid" 2>/dev/null || true
    done
fi

# Record initial counts
INITIAL_HP_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_healthprofessional" | tr -d '[:space:]')
INITIAL_PARTY_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM party_party" | tr -d '[:space:]')

echo "${INITIAL_HP_COUNT:-0}" > /tmp/initial_hp_count.txt
echo "${INITIAL_PARTY_COUNT:-0}" > /tmp/initial_party_count.txt

echo "Initial health professional count: ${INITIAL_HP_COUNT:-0}"
echo "Initial party count: ${INITIAL_PARTY_COUNT:-0}"

# Start Firefox and log into GNU Health
echo "Starting Firefox and logging into GNU Health..."
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# Focus and maximize Firefox
focus_firefox
sleep 2

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png
echo "Initial state screenshot saved"

echo "=== Task setup complete ==="