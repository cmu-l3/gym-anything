#!/bin/bash
set -e
echo "=== Setting up Triage Batch Processing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Database Prep: Clean & Seed
# ============================================================
echo "Preparing database..."

# Ensure MySQL is running
ensure_medintux_running

# Helper to run SQL
run_sql() {
    mysql -u root DrTuxTest -N -e "$1" 2>/dev/null
}

# Clear our specific test subjects to ensure known state
# Alice MARTIN (Existing)
delete_patient "MARTIN" "Alice"
# Bob DUBOIS (New - ensure he is GONE)
delete_patient "DUBOIS" "Bob"
# Charlie LEFEBVRE (Existing)
delete_patient "LEFEBVRE" "Charlie"

# Re-create Existing Patients (Alice & Charlie)
# We use the utility function if available, or raw SQL
echo "Seeding existing patients..."

# Alice
GUID_ALICE="TRIAGE-TEST-ALICE"
insert_patient "$GUID_ALICE" "MARTIN" "Alice" "1980-05-15" "F" "Mme" "10 Rue des Lilas" "75012" "Paris" "0601020304" "2800575012001"

# Charlie
GUID_CHARLIE="TRIAGE-TEST-CHARLIE"
insert_patient "$GUID_CHARLIE" "LEFEBVRE" "Charlie" "1975-03-10" "M" "M." "45 Avenue de la République" "69001" "Lyon" "0699887766" "1750369001002"

echo "Database seeded."

# ============================================================
# 2. Create Triage List File
# ============================================================
echo "Creating triage list on Desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/triage_list.txt << EOF
=== URGENT TRIAGE LIST ===
Date: $(date +%Y-%m-%d)

1. PATIENT: MARTIN Alice
   DOB: 1980-05-15
   SYMPTOM: High fever, coughing
   VITALS: Temp 39.5C, BP 120/80

2. PATIENT: DUBOIS Bob
   DOB: 1992-11-20
   SYMPTOM: Sore throat, difficulty swallowing
   VITALS: Temp 38.2C, BP 135/85
   ADDRESS: 8 Rue de la Paix, 33000 Bordeaux (NEW PATIENT)

3. PATIENT: LEFEBVRE Charlie
   DOB: 1975-03-10
   SYMPTOM: Chest pain (mild), fatigue
   VITALS: Temp 37.1C, BP 150/95
EOF

chmod 644 /home/ga/Desktop/triage_list.txt
chown ga:ga /home/ga/Desktop/triage_list.txt

# ============================================================
# 3. Record Initial State (for verification)
# ============================================================
# We need to count items linked to these patients to see if new notes are added
# Count items in IndexNomPrenom where IDDos matches the patient GUID
# and Type is NOT 'Dossier' (which implies it's a sub-element like a note)

count_subitems() {
    local guid="$1"
    run_sql "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid' AND FchGnrl_Type!='Dossier'"
}

ALICE_ITEMS=$(count_subitems "$GUID_ALICE")
CHARLIE_ITEMS=$(count_subitems "$GUID_CHARLIE")

cat > /tmp/initial_counts.json << JSON
{
    "alice_items": ${ALICE_ITEMS:-0},
    "charlie_items": ${CHARLIE_ITEMS:-0},
    "bob_exists": 0
}
JSON

echo "Initial item counts recorded."

# ============================================================
# 4. App Launch
# ============================================================
# Launch MedinTux Manager if not running
launch_medintux_manager

# Ensure Desktop is visible (minimize windows if needed, though manager should be focused)
# We want the agent to see the text file icon if possible, but manager is maximized.
# Agent knows to look on Desktop.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="