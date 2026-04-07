#!/bin/bash
echo "=== Exporting Triage Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Database Verification
run_sql() {
    mysql -u root DrTuxTest -N -e "$1" 2>/dev/null
}

echo "Querying database for patient records..."

# CHECK ALICE (Should exist, No duplicates)
ALICE_COUNT=$(run_sql "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='MARTIN' AND FchGnrl_Prenom='Alice' AND FchGnrl_Type='Dossier'")
ALICE_GUID=$(run_sql "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='MARTIN' AND FchGnrl_Prenom='Alice' AND FchGnrl_Type='Dossier' LIMIT 1")
ALICE_FINAL_ITEMS=$(run_sql "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$ALICE_GUID' AND FchGnrl_Type!='Dossier'")

# CHECK BOB (Should exist now, count 1)
BOB_COUNT=$(run_sql "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUBOIS' AND FchGnrl_Prenom='Bob' AND FchGnrl_Type='Dossier'")
BOB_GUID=$(run_sql "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUBOIS' AND FchGnrl_Prenom='Bob' AND FchGnrl_Type='Dossier' LIMIT 1")
BOB_FINAL_ITEMS=$(run_sql "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$BOB_GUID' AND FchGnrl_Type!='Dossier'")

# CHECK CHARLIE (Should exist, No duplicates)
CHARLIE_COUNT=$(run_sql "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='LEFEBVRE' AND FchGnrl_Prenom='Charlie' AND FchGnrl_Type='Dossier'")
CHARLIE_GUID=$(run_sql "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='LEFEBVRE' AND FchGnrl_Prenom='Charlie' AND FchGnrl_Type='Dossier' LIMIT 1")
CHARLIE_FINAL_ITEMS=$(run_sql "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$CHARLIE_GUID' AND FchGnrl_Type!='Dossier'")

# Retrieve Initial Counts
INITIAL_ALICE_ITEMS=0
INITIAL_CHARLIE_ITEMS=0
if [ -f /tmp/initial_counts.json ]; then
    INITIAL_ALICE_ITEMS=$(grep -o '"alice_items": [0-9]*' /tmp/initial_counts.json | cut -d' ' -f2)
    INITIAL_CHARLIE_ITEMS=$(grep -o '"charlie_items": [0-9]*' /tmp/initial_counts.json | cut -d' ' -f2)
fi

# Calculate deltas (New items added)
ALICE_DELTA=$((ALICE_FINAL_ITEMS - INITIAL_ALICE_ITEMS))
CHARLIE_DELTA=$((CHARLIE_FINAL_ITEMS - INITIAL_CHARLIE_ITEMS))
# Bob didn't exist, so all items are new
BOB_DELTA=${BOB_FINAL_ITEMS:-0}

# App Running Check
APP_RUNNING="false"
if pgrep -f "Manager.exe" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "alice": {
        "exists": true,
        "record_count": ${ALICE_COUNT:-0},
        "notes_added": $ALICE_DELTA,
        "guid": "$ALICE_GUID"
    },
    "bob": {
        "exists": $( [ "${BOB_COUNT:-0}" -gt 0 ] && echo "true" || echo "false" ),
        "record_count": ${BOB_COUNT:-0},
        "notes_added": $BOB_DELTA,
        "guid": "$BOB_GUID"
    },
    "charlie": {
        "exists": true,
        "record_count": ${CHARLIE_COUNT:-0},
        "notes_added": $CHARLIE_DELTA,
        "guid": "$CHARLIE_GUID"
    },
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="