#!/bin/bash
# Setup script for polypharmacy_review_and_update task
# Seeds 4 patients with medication safety issues (real drug combinations used in clinical practice):
#   MARTIN Sophie   — Dual RAAS blockade (Ramipril + Valsartan, contraindicated combination)
#   BERNARD Pierre  — NSAID allergy but NSAID (Ibuprofene) active in prescription
#   MOREAU Francois — Duplicate beta-blockers (Atenolol + Bisoprolol simultaneously)
#   LEROY Isabelle  — Metformin prescribed despite severe renal insufficiency (DFG < 30, absolute CI)

echo "=== Setting up polypharmacy_review_and_update ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type medintux_query &>/dev/null; then
    medintux_query() { mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

# Kill any running MedinTux instances before DB operations (avoid caching conflicts)
pkill -f Manager.exe 2>/dev/null || true
pkill -f wine 2>/dev/null || true
sleep 3

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Patient GUIDs (from post_start seed data)
GUID_MARTIN="0E78F6AF-9396-4000-A4C2-29FFE96C6205"
GUID_BERNARD="EFE754AE-2CFD-4C06-A3F9-6D1AE2B18ABC"
GUID_MOREAU="E87A5020-F471-4046-96C3-59852DF10DE2"
GUID_LEROY="4E8D739F-2A13-4CA7-907D-2CC8B1E5AC71"

echo "Verifying target patients exist..."
for GUID in "$GUID_MARTIN" "$GUID_BERNARD" "$GUID_MOREAU" "$GUID_LEROY"; do
    COUNT=$(medintux_query "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID';")
    if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
        echo "ERROR: Patient with GUID $GUID not found in database!"
        exit 1
    fi
done
echo "All 4 target patients confirmed present."

# Remove any existing rubric data for these 4 patients so we start clean
echo "Cleaning existing rubrics for target patients..."
python3 << 'PYEOF'
import pymysql

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

guids = [
    '0E78F6AF-9396-4000-A4C2-29FFE96C6205',  # MARTIN Sophie
    'EFE754AE-2CFD-4C06-A3F9-6D1AE2B18ABC',  # BERNARD Pierre
    'E87A5020-F471-4046-96C3-59852DF10DE2',  # MOREAU Francois
    '4E8D739F-2A13-4CA7-907D-2CC8B1E5AC71',  # LEROY Isabelle
]

for guid in guids:
    # Get PrimKeys of existing rubrics for this patient
    cursor.execute(
        "SELECT RbDate_PrimKey FROM RubriquesHead WHERE RbDate_IDDos=%s",
        (guid,)
    )
    pks = [row[0] for row in cursor.fetchall()]
    if pks:
        placeholders = ','.join(['%s'] * len(pks))
        cursor.execute(f"DELETE FROM RubriquesBlobs WHERE RbDate_PrimKey IN ({placeholders})", pks)
        cursor.execute(f"DELETE FROM RubriquesHead WHERE RbDate_PrimKey IN ({placeholders})", pks)

conn.commit()
conn.close()
print("Cleaned existing rubrics for 4 target patients.")
PYEOF

# Now insert the scenario data: terrain + old prescriptions with medication safety issues
echo "Inserting medication safety scenario data..."
python3 << 'PYEOF'
import pymysql

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

def get_refpk(guid):
    cursor.execute("SELECT FchPat_RefPk FROM fchpat WHERE FchPat_GUID_Doss=%s", (guid,))
    row = cursor.fetchone()
    return row[0] if row else 0

def insert_rubric(guid, type_rub, nom_date, sub_type, date_str, blob_data, fin_date=None):
    refpk = get_refpk(guid)
    cursor.execute("""
        INSERT INTO RubriquesHead
        (RbDate_IDDos, RbDate_TypeRub, RbDate_NomDate, RbDate_SubTypeRub, RbDate_Date,
         RbDate_CreateUser, RbDate_Ref_NumDoss, RbDate_Fin)
        VALUES (%s, %s, %s, %s, %s, 'admin', %s, %s)
    """, (guid, type_rub, nom_date, sub_type, date_str, refpk, fin_date))
    head_pk = cursor.lastrowid
    cursor.execute("""
        INSERT INTO RubriquesBlobs (RbDate_PrimKey, RbDate_DataRub, RbDate_IDDos)
        VALUES (%s, %s, %s)
    """, (head_pk, blob_data.encode('latin1', errors='replace'), guid))
    cursor.execute(
        "UPDATE RubriquesHead SET RbDate_RefBlobs_PrimKey=%s WHERE RbDate_PrimKey=%s",
        (head_pk, head_pk)
    )
    return head_pk

# ────────────────────────────────────────────────────────────────────────────
# MARTIN Sophie (GUID: 0E78F6AF-9396-4000-A4C2-29FFE96C6205)
# Issue: Dual RAAS blockade — Ramipril (ACE inhibitor) + Valsartan (ARB) co-prescribed
# Clinical rationale: ACC/AHA guidelines 2017 classify this as a Class III (Harm) recommendation
# ────────────────────────────────────────────────────────────────────────────
GUID_MARTIN = '0E78F6AF-9396-4000-A4C2-29FFE96C6205'

terrain_martin = (
    "[Antecedents]\n"
    "   Hypertension arterielle = Medicaux , Actif , ~I10~ ,  ,  , \n"
    "   Diabete type 2 = Medicaux , Actif , ~E11~ ,  ,  , \n"
    "   Dyslipidaemie = Medicaux , Actif , ~E78.5~ ,  ,  , \n"
)
insert_rubric(GUID_MARTIN, 20060000, 'Terrain', 'Default SubType',
              '2023-06-10 09:00:00', terrain_martin)

# Old prescription (dated 2024-10) containing the dangerous combination
ordo_martin = (
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>\n'
    '<ordotext>\n'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">\n'
    '<p>Ramipril 5mg cp : 1 comprimes le matin</p>\n'
    '<p>Valsartan 80mg cp : 1 comprimes le soir</p>\n'
    '<p>Metformine 850mg cp : 1 comprimes matin et soir pendant les repas</p>\n'
    '<p>Atorvastatine 20mg cp : 1 comprimes le soir</p>\n'
    '</body></html>\n'
    '</ordotext>\n'
)
insert_rubric(GUID_MARTIN, 20020100, 'Ordonnance octobre 2024', 'Default SubType',
              '2024-10-15 10:30:00', ordo_martin, fin_date='2025-01-15 10:30:00')

# ────────────────────────────────────────────────────────────────────────────
# BERNARD Pierre (GUID: EFE754AE-2CFD-4C06-A3F9-6D1AE2B18ABC)
# Issue: NSAID allergy documented in terrain, but Ibuprofene 400mg active in prescription
# ────────────────────────────────────────────────────────────────────────────
GUID_BERNARD = 'EFE754AE-2CFD-4C06-A3F9-6D1AE2B18ABC'

terrain_bernard = (
    "[Antecedents]\n"
    "   IBUPROFENE = Allergique , Actif , (-3533524-) ,  ,  , \n"
    "   ASPIRINE = Allergique , Actif , (-3539874-) ,  ,  , \n"
    "   Arthrose lombaire = Medicaux , Actif , ~M47.8~ , diagnostiquee en 2019 ,  , \n"
    "   Insuffisance cardiaque legere (NYHA II) = Medicaux , Actif , ~I50.9~ ,  ,  , \n"
)
insert_rubric(GUID_BERNARD, 20060000, 'Terrain', 'Default SubType',
              '2022-03-12 14:00:00', terrain_bernard)

ordo_bernard = (
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>\n'
    '<ordotext>\n'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">\n'
    '<p>Ibuprofene 400mg cp : 1 comprimes 3 fois par jour pendant les repas (douleurs dorsales)</p>\n'
    '<p>Bisoprolol 2.5mg cp : 1 comprimes le matin (insuffisance cardiaque)</p>\n'
    '<p>Furosemide 40mg cp : 1 comprimes le matin (insuffisance cardiaque)</p>\n'
    '</body></html>\n'
    '</ordotext>\n'
)
insert_rubric(GUID_BERNARD, 20020100, 'Ordonnance septembre 2025', 'Default SubType',
              '2025-09-05 11:00:00', ordo_bernard, fin_date='2025-12-05 11:00:00')

# ────────────────────────────────────────────────────────────────────────────
# MOREAU Francois (GUID: E87A5020-F471-4046-96C3-59852DF10DE2)
# Issue: Duplicate beta-blockers — Atenolol 50mg (old prescription) + Bisoprolol 5mg (new prescription)
# Both are beta-1 selective blockers — additive bradycardia and hypotension risk
# ────────────────────────────────────────────────────────────────────────────
GUID_MOREAU = 'E87A5020-F471-4046-96C3-59852DF10DE2'

terrain_moreau = (
    "[Antecedents]\n"
    "   Hypertension arterielle = Medicaux , Actif , ~I10~ , depuis 2010 ,  , \n"
    "   Angor stable = Medicaux , Actif , ~I20.8~ , diagnostique en 2018 ,  , \n"
    "   Tabagisme sevré = Medicaux , Passe , ~F17.2~ , arrete en 2015 ,  , \n"
)
insert_rubric(GUID_MOREAU, 20060000, 'Terrain', 'Default SubType',
              '2021-09-20 10:00:00', terrain_moreau)

# Old prescription (Atenolol — still active)
ordo_moreau_old = (
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>\n'
    '<ordotext>\n'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">\n'
    '<p>Atenolol 50mg cp : 1 comprimes le matin (HTA et angor)</p>\n'
    '<p>Amlodipine 5mg cp : 1 comprimes le soir (HTA)</p>\n'
    '<p>Aspirine 100mg cp : 1 comprimes le matin (angor)</p>\n'
    '</body></html>\n'
    '</ordotext>\n'
)
insert_rubric(GUID_MOREAU, 20020100, 'Ordonnance fevrier 2025', 'Default SubType',
              '2025-02-10 09:00:00', ordo_moreau_old, fin_date='2025-05-10 09:00:00')

# Newer prescription (Bisoprolol added by cardiologist follow-up, old Atenolol not removed)
ordo_moreau_new = (
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>\n'
    '<ordotext>\n'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">\n'
    '<p>Atenolol 50mg cp : 1 comprimes le matin</p>\n'
    '<p>Bisoprolol 5mg cp : 1 comprimes le matin</p>\n'
    '<p>Amlodipine 5mg cp : 1 comprimes le soir</p>\n'
    '<p>Aspirine 100mg cp : 1 comprimes le matin</p>\n'
    '</body></html>\n'
    '</ordotext>\n'
)
insert_rubric(GUID_MOREAU, 20020100, 'Ordonnance novembre 2025', 'Default SubType',
              '2025-11-18 14:00:00', ordo_moreau_new, fin_date='2026-02-18 14:00:00')

# ────────────────────────────────────────────────────────────────────────────
# LEROY Isabelle (GUID: 4E8D739F-2A13-4CA7-907D-2CC8B1E5AC71)
# Issue: Metformin 850mg prescribed — absolute contraindication with severe CKD (DFG < 30)
# Per ANSM French guidelines: Metformin CI when DFG < 30 ml/min/1.73m²
# ────────────────────────────────────────────────────────────────────────────
GUID_LEROY = '4E8D739F-2A13-4CA7-907D-2CC8B1E5AC71'

terrain_leroy = (
    "[Antecedents]\n"
    "   Insuffisance renale chronique severe (DFG 22 ml/min) = Medicaux , Actif , ~N18.4~ , nephrologue Dr. Blanc suivi regulier ,  , \n"
    "   Diabete type 2 = Medicaux , Actif , ~E11~ , diagnostique 2016 HbA1c 8.1% ,  , \n"
    "   Hypertension arterielle = Medicaux , Actif , ~I10~ , bien controlee ,  , \n"
    "   Anemie renale = Medicaux , Actif , ~N18.9~ , sous EPO ,  , \n"
)
insert_rubric(GUID_LEROY, 20060000, 'Terrain', 'Default SubType',
              '2023-11-05 10:00:00', terrain_leroy)

ordo_leroy = (
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>\n'
    '<ordotext>\n'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">\n'
    '<p>Metformine 850mg cp : 1 comprimes matin et soir pendant les repas (diabete)</p>\n'
    '<p>Ramipril 5mg cp : 1 comprimes le matin (HTA et nephroprotection)</p>\n'
    '<p>Furosemide 40mg cp : 1 comprimes le matin (retention hydrosodee)</p>\n'
    '<p>Darbepoetin alfa 40 mcg : 1 injection SC toutes les 2 semaines (anemie renale)</p>\n'
    '</body></html>\n'
    '</ordotext>\n'
)
insert_rubric(GUID_LEROY, 20020100, 'Ordonnance janvier 2026', 'Default SubType',
              '2026-01-10 10:30:00', ordo_leroy, fin_date='2026-04-10 10:30:00')

conn.commit()
conn.close()
print("Medication safety scenario data inserted for all 4 patients.")
PYEOF

# Record baseline counts (rubric counts before agent acts)
echo "Recording baseline state..."
BASELINE_MARTIN=$(medintux_query "SELECT COUNT(*) FROM RubriquesHead WHERE RbDate_IDDos='0E78F6AF-9396-4000-A4C2-29FFE96C6205';")
BASELINE_BERNARD=$(medintux_query "SELECT COUNT(*) FROM RubriquesHead WHERE RbDate_IDDos='EFE754AE-2CFD-4C06-A3F9-6D1AE2B18ABC';")
BASELINE_MOREAU=$(medintux_query "SELECT COUNT(*) FROM RubriquesHead WHERE RbDate_IDDos='E87A5020-F471-4046-96C3-59852DF10DE2';")
BASELINE_LEROY=$(medintux_query "SELECT COUNT(*) FROM RubriquesHead WHERE RbDate_IDDos='4E8D739F-2A13-4CA7-907D-2CC8B1E5AC71';")

echo "$BASELINE_MARTIN" > /tmp/baseline_martin
echo "$BASELINE_BERNARD" > /tmp/baseline_bernard
echo "$BASELINE_MOREAU" > /tmp/baseline_moreau
echo "$BASELINE_LEROY" > /tmp/baseline_leroy

echo "Baselines: MARTIN=$BASELINE_MARTIN BERNARD=$BASELINE_BERNARD MOREAU=$BASELINE_MOREAU LEROY=$BASELINE_LEROY"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Launch MedinTux Manager
echo "Launching MedinTux Manager..."
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/polypharmacy_start.png 2>/dev/null || true

echo "=== Setup Complete: polypharmacy_review_and_update ==="
