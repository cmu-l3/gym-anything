#!/bin/bash
# Setup script for new_patient_complex_entry task
# Ensures BONNET Elise does NOT exist in the database (clean slate for the agent to create her)
# and that the environment is ready.

echo "=== Setting up new_patient_complex_entry ==="

source /workspace/scripts/task_utils.sh

if ! type medintux_query &>/dev/null; then
    medintux_query() { mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

pkill -f Manager.exe 2>/dev/null || true
pkill -f wine 2>/dev/null || true
sleep 3

systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Delete BONNET Elise if she already exists (from a previous run)
echo "Ensuring BONNET Elise is not already in the database..."
python3 << 'PYEOF'
import pymysql

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

# Find all records for BONNET Elise
cursor.execute(
    "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='BONNET' AND FchGnrl_Prenom='Elise'"
)
guids = [row[0] for row in cursor.fetchall()]

for guid in guids:
    # Delete rubrics
    cursor.execute("SELECT RbDate_PrimKey FROM RubriquesHead WHERE RbDate_IDDos=%s", (guid,))
    pks = [row[0] for row in cursor.fetchall()]
    if pks:
        placeholders = ','.join(['%s'] * len(pks))
        cursor.execute(f"DELETE FROM RubriquesBlobs WHERE RbDate_PrimKey IN ({placeholders})", pks)
        cursor.execute(f"DELETE FROM RubriquesHead WHERE RbDate_PrimKey IN ({placeholders})", pks)
    # Delete agenda entries
    cursor.execute("DELETE FROM agenda WHERE GUID=%s", (guid,))
    # Delete from patient tables
    cursor.execute("DELETE FROM fchpat WHERE FchPat_GUID_Doss=%s", (guid,))
    cursor.execute("DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos=%s", (guid,))

conn.commit()
conn.close()
if guids:
    print(f"Deleted {len(guids)} existing BONNET Elise record(s) and all associated data.")
else:
    print("BONNET Elise not in database — clean state confirmed.")
PYEOF

# Record baseline patient count
BASELINE_PATIENTS=$(medintux_query "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier';")
BASELINE_PATIENTS=${BASELINE_PATIENTS:-0}
echo "$BASELINE_PATIENTS" > /tmp/baseline_patient_count
echo "Baseline patient count: $BASELINE_PATIENTS"

# Record baseline agenda PrimKey
BASELINE_AGENDA_PK=$(medintux_query "SELECT COALESCE(MAX(PrimKey), 0) FROM agenda;")
BASELINE_AGENDA_PK=${BASELINE_AGENDA_PK:-0}
echo "$BASELINE_AGENDA_PK" > /tmp/baseline_agenda_pk
echo "Baseline agenda max PrimKey: $BASELINE_AGENDA_PK"

date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

echo "Launching MedinTux Manager..."
launch_medintux_manager

take_screenshot /tmp/new_patient_complex_start.png 2>/dev/null || true

echo "=== Setup Complete: new_patient_complex_entry ==="
