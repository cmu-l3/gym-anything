#!/bin/bash
set -e
echo "=== Setting up task: add_patient_family_info ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ─── Ensure HospitalRun services are running ────────────────────────────────
echo "[setup] Checking HospitalRun services..."
cd /home/ga/hospitalrun

# Wait for CouchDB
echo "[setup] Waiting for CouchDB..."
for i in $(seq 1 30); do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:5984/ 2>/dev/null | grep -q "200"; then
        echo "[setup] CouchDB is ready"
        break
    fi
    sleep 2
done

# Wait for HospitalRun app
echo "[setup] Waiting for HospitalRun app..."
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "[setup] HospitalRun app is ready"
        break
    fi
    sleep 3
done

# ─── Fix offline sync / PouchDB loading issue ───────────────────────────────
# Critical for this environment to function correctly
echo "[setup] Applying offline sync fix..."
fix_offline_sync

# ─── Verify/Create patient Maria Santos ─────────────────────────────────────
echo "[setup] Verifying patient Maria Santos exists..."
# Check if patient exists by ID
MARIA_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_001" 2>/dev/null || echo "{}")
EXISTS=$(echo "$MARIA_DOC" | python3 -c "import sys, json; print('true' if '_id' in json.load(sys.stdin) else 'false')" 2>/dev/null || echo "false")

if [ "$EXISTS" != "true" ]; then
    echo "[setup] Maria Santos not found, creating her..."
    MARIA_JSON=$(cat <<'EOFMARIA'
{
    "_id": "patient_p1_001",
    "type": "patient",
    "data": {
        "given_name": "Maria",
        "family_name": "Santos",
        "sex": "Female",
        "birthday": "1969-03-14T00:00:00.000Z",
        "email": "maria.santos@example.com",
        "phone": "555-0101",
        "address": "742 Evergreen Terrace",
        "friendlyId": "P00001",
        "firstName": "Maria",
        "lastName": "Santos"
    },
    "patientId": "P00001"
}
EOFMARIA
)
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_001" \
        -H "Content-Type: application/json" \
        -d "$MARIA_JSON" > /dev/null 2>&1 || true
    echo "[setup] Maria Santos created"
fi

# ─── Record initial document count ──────────────────────────────────────────
# We use this to detect if new documents were actually created
echo "[setup] Recording initial document count..."
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs" 2>/dev/null | grep -o '"total_rows":[0-9]*' | cut -d: -f2 || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_doc_count.txt

# ─── Launch Firefox and login ────────────────────────────────────────────────
echo "[setup] Launching Firefox..."

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Clear Firefox profile to avoid stale PouchDB state
rm -rf /home/ga/.mozilla/firefox/*.default*/storage 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox --no-remote 'http://localhost:3000/' &" 2>/dev/null
sleep 8

# Wait for Firefox window
echo "[setup] Waiting for Firefox window..."
for i in $(seq 1 20); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|hospitalrun"; then
        break
    fi
    sleep 2
done

# Maximize Firefox
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait for HospitalRun to load
echo "[setup] Waiting for HospitalRun to finish loading..."
sleep 15

# Login to HospitalRun
echo "[setup] Logging into HospitalRun..."
navigate_firefox_to "http://localhost:3000/#/login"
sleep 5

# Enter credentials
DISPLAY=:1 xdotool key Tab
sleep 0.3
DISPLAY=:1 xdotool type --delay 30 "hradmin"
sleep 0.3
DISPLAY=:1 xdotool key Tab
sleep 0.3
DISPLAY=:1 xdotool type --delay 30 "test"
sleep 0.3
DISPLAY=:1 xdotool key Return
sleep 8

# Take initial state screenshot
echo "[setup] Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="