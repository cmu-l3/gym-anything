#!/bin/bash
# Setup script for overdue_followup_scheduling task
#
# Creates a realistic scenario: 5 chronic patients with outdated consultations (>6 months ago)
# and 2 patients with recent consultations (not overdue).
# Also adds terrain data for all 7 to indicate their chronic conditions.
# The agent must DISCOVER which patients are overdue by reviewing their records.

echo "=== Setting up overdue_followup_scheduling ==="

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

# Patient GUIDs
GUID_PETIT="0C1E07E8-F19E-410F-8F46-403388A0924D"
GUID_DURAND="C4B37BEC-5F7F-4A56-80A1-1ADB9B6CC52E"
GUID_GIRARD="826A8DE5-F007-4040-BB91-74F2E5C8DA14"
GUID_MOREL="BA73A90A-B637-4321-AB65-952E0FA0F040"
GUID_HENRY="D12A6F18-4C10-4DCC-ABE6-15699EBB7C24"
GUID_ROUX="61FD5B15-0CA8-42C4-A4D6-59B542BD7EA9"
GUID_BLANC="E5D70363-94D8-453C-8E1A-67D9AB289F87"

echo "Verifying target patients exist..."
for GUID in "$GUID_PETIT" "$GUID_DURAND" "$GUID_GIRARD" "$GUID_MOREL" "$GUID_HENRY" "$GUID_ROUX" "$GUID_BLANC"; do
    COUNT=$(medintux_query "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID';")
    if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
        echo "ERROR: Patient $GUID not found!"
        exit 1
    fi
done
echo "All 7 target patients confirmed."

# Clean existing rubrics and any existing agenda entries for these patients
echo "Cleaning existing data for target patients..."
python3 << 'PYEOF'
import pymysql

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

all_guids = [
    '0C1E07E8-F19E-410F-8F46-403388A0924D',  # PETIT Nathalie
    'C4B37BEC-5F7F-4A56-80A1-1ADB9B6CC52E',  # DURAND Christophe
    '826A8DE5-F007-4040-BB91-74F2E5C8DA14',  # GIRARD Michel
    'BA73A90A-B637-4321-AB65-952E0FA0F040',  # MOREL Sylvie
    'D12A6F18-4C10-4DCC-ABE6-15699EBB7C24',  # HENRY Emmanuel
    '61FD5B15-0CA8-42C4-A4D6-59B542BD7EA9',  # ROUX Celine
    'E5D70363-94D8-453C-8E1A-67D9AB289F87',  # BLANC David
]

for guid in all_guids:
    cursor.execute("SELECT RbDate_PrimKey FROM RubriquesHead WHERE RbDate_IDDos=%s", (guid,))
    pks = [row[0] for row in cursor.fetchall()]
    if pks:
        placeholders = ','.join(['%s'] * len(pks))
        cursor.execute(f"DELETE FROM RubriquesBlobs WHERE RbDate_PrimKey IN ({placeholders})", pks)
        cursor.execute(f"DELETE FROM RubriquesHead WHERE RbDate_PrimKey IN ({placeholders})", pks)

# Remove existing agenda entries for these patients
cursor.execute("DELETE FROM agenda WHERE GUID IN %s", (all_guids,))

conn.commit()
conn.close()
print("Cleaned existing data for 7 target patients.")
PYEOF

# Insert terrain + consultation history
echo "Inserting consultation history scenario..."
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
    cursor.execute(
        "INSERT INTO RubriquesBlobs (RbDate_PrimKey, RbDate_DataRub, RbDate_IDDos) VALUES (%s, %s, %s)",
        (head_pk, blob_data.encode('latin1', errors='replace'), guid)
    )
    cursor.execute(
        "UPDATE RubriquesHead SET RbDate_RefBlobs_PrimKey=%s WHERE RbDate_PrimKey=%s",
        (head_pk, head_pk)
    )
    return head_pk

# ── Overdue patients (last consultation before 2025-09-02) ──────────────────

# PETIT Nathalie — Diabete type 2, last consult 2025-06-15
GUID_PETIT = '0C1E07E8-F19E-410F-8F46-403388A0924D'
insert_rubric(GUID_PETIT, 20060000, 'Terrain', 'Default SubType', '2023-03-10 09:00:00',
    "[Antecedents]\n"
    "   Diabete type 2 = Medicaux , Actif , ~E11~ , sous Metformine + Sitagliptine ,  , \n"
    "   Surpoids = Medicaux , Actif , ~E65~ , IMC 28.5 ,  , \n")
cons_blob_petit = (
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 15/06/2025 - Diabete type 2</p>'
    '<p>TA: 128/80 - Poids: 74kg - HbA1c: 7.4%</p>'
    '<p>Renouvellement traitement. Prochain bilan dans 3 mois.</p>'
    '</body></html>\n'
)
insert_rubric(GUID_PETIT, 20030000, 'Consultation juin 2025', 'Default SubType',
              '2025-06-15 10:00:00', cons_blob_petit)

# DURAND Christophe — Hypertension, last consult 2025-07-10
GUID_DURAND = 'C4B37BEC-5F7F-4A56-80A1-1ADB9B6CC52E'
insert_rubric(GUID_DURAND, 20060000, 'Terrain', 'Default SubType', '2022-11-05 10:00:00',
    "[Antecedents]\n"
    "   Hypertension arterielle = Medicaux , Actif , ~I10~ , sous Amlodipine + Perindopril ,  , \n"
    "   Surpoids = Medicaux , Actif , ~E65~ ,  ,  , \n")
cons_blob_durand = (
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 10/07/2025 - Suivi HTA</p>'
    '<p>TA: 148/92 - Pouls: 72/min - Poids: 91kg</p>'
    '<p>HTA mal equilibree. Majoration Perindopril 10mg. Recontroler dans 3 mois.</p>'
    '</body></html>\n'
)
insert_rubric(GUID_DURAND, 20030000, 'Consultation juillet 2025', 'Default SubType',
              '2025-07-10 11:00:00', cons_blob_durand)

# GIRARD Michel — Hypothyroidie, last consult 2025-05-22
GUID_GIRARD = '826A8DE5-F007-4040-BB91-74F2E5C8DA14'
insert_rubric(GUID_GIRARD, 20060000, 'Terrain', 'Default SubType', '2020-06-14 09:00:00',
    "[Antecedents]\n"
    "   Hypothyroidie = Medicaux , Actif , ~E03.9~ , sous Levothyroxine 75mcg ,  , \n"
    "   Bradycardie sinusale = Medicaux , Actif , ~R00.1~ ,  ,  , \n")
cons_blob_girard = (
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 22/05/2025 - Suivi hypothyroidie</p>'
    '<p>TSH: 3.2 mUI/L (normale). Traitement adapte.</p>'
    '<p>Renouvellement Levothyroxine 75mcg. Bilan TSH dans 6 mois.</p>'
    '</body></html>\n'
)
insert_rubric(GUID_GIRARD, 20030000, 'Consultation mai 2025', 'Default SubType',
              '2025-05-22 09:30:00', cons_blob_girard)

# MOREL Sylvie — Asthme, last consult 2025-08-01
GUID_MOREL = 'BA73A90A-B637-4321-AB65-952E0FA0F040'
insert_rubric(GUID_MOREL, 20060000, 'Terrain', 'Default SubType', '2019-04-22 10:00:00',
    "[Antecedents]\n"
    "   Asthme moderatement persistant = Medicaux , Actif , ~J45.1~ , VEMS 68% theorique ,  , \n"
    "   Rhinite allergique = Medicaux , Actif , ~J30.1~ , allergique aux acariens ,  , \n")
cons_blob_morel = (
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 01/08/2025 - Suivi asthme</p>'
    '<p>Absence de crise depuis 3 mois. Traitement de fond: Symbicort 200/6. Salbutamol si besoin.</p>'
    '<p>EFR a refaire dans 6 mois.</p>'
    '</body></html>\n'
)
insert_rubric(GUID_MOREL, 20030000, 'Consultation aout 2025', 'Default SubType',
              '2025-08-01 14:00:00', cons_blob_morel)

# HENRY Emmanuel — Lombalgies chroniques, last consult 2025-08-20
GUID_HENRY = 'D12A6F18-4C10-4DCC-ABE6-15699EBB7C24'
insert_rubric(GUID_HENRY, 20060000, 'Terrain', 'Default SubType', '2021-09-15 10:00:00',
    "[Antecedents]\n"
    "   Lombalgies chroniques = Medicaux , Actif , ~M54.5~ , hernie discale L4-L5 connue ,  , \n"
    "   Syndrome anxiodepressif = Medicaux , Actif , ~F41.2~ , sous ISRS ,  , \n")
cons_blob_henry = (
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 20/08/2025 - Lombalgies chroniques</p>'
    '<p>EVA douleur: 5/10. Kinesitherapie en cours (10 seances). Paracetamol 1g x3/j.</p>'
    '<p>Revoir dans 6 mois ou si aggravation.</p>'
    '</body></html>\n'
)
insert_rubric(GUID_HENRY, 20030000, 'Consultation aout 2025 (2)', 'Default SubType',
              '2025-08-20 10:30:00', cons_blob_henry)

# ── NOT overdue — recent consultations (after 2025-09-02) ──────────────────

# ROUX Celine — last consult 2025-11-20
GUID_ROUX = '61FD5B15-0CA8-42C4-A4D6-59B542BD7EA9'
insert_rubric(GUID_ROUX, 20060000, 'Terrain', 'Default SubType', '2024-02-01 10:00:00',
    "[Antecedents]\n"
    "   Diabete type 1 = Medicaux , Actif , ~E10~ , sous insulinotherapie ,  , \n")
cons_blob_roux = (
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 20/11/2025 - Suivi diabete type 1</p>'
    '<p>HbA1c: 6.9%. Bonne compliance. Pompe a insuline reglage OK.</p>'
    '</body></html>\n'
)
insert_rubric(GUID_ROUX, 20030000, 'Consultation novembre 2025', 'Default SubType',
              '2025-11-20 09:00:00', cons_blob_roux)

# BLANC David — last consult 2025-12-10
GUID_BLANC = 'E5D70363-94D8-453C-8E1A-67D9AB289F87'
insert_rubric(GUID_BLANC, 20060000, 'Terrain', 'Default SubType', '2025-01-10 10:00:00',
    "[Antecedents]\n"
    "   Hypertension arterielle = Medicaux , Actif , ~I10~ , decouverte recente ,  , \n")
cons_blob_blanc = (
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 10/12/2025 - Suivi HTA</p>'
    '<p>TA: 132/84. Ramipril 5mg bien tolere. Renouvellement.</p>'
    '</body></html>\n'
)
insert_rubric(GUID_BLANC, 20030000, 'Consultation decembre 2025', 'Default SubType',
              '2025-12-10 11:00:00', cons_blob_blanc)

conn.commit()
conn.close()
print("Consultation history scenario inserted for 7 patients.")
PYEOF

# Record baseline agenda counts
echo "Recording baseline state..."
BASELINE_AGENDA=$(medintux_query "SELECT COUNT(*) FROM agenda WHERE Date_Time > NOW();")
BASELINE_AGENDA=${BASELINE_AGENDA:-0}
echo "$BASELINE_AGENDA" > /tmp/baseline_agenda_count

# Save overdue patient GUIDs for verifier reference
cat > /tmp/overdue_guids.txt << 'EOF'
0C1E07E8-F19E-410F-8F46-403388A0924D
C4B37BEC-5F7F-4A56-80A1-1ADB9B6CC52E
826A8DE5-F007-4040-BB91-74F2E5C8DA14
BA73A90A-B637-4321-AB65-952E0FA0F040
D12A6F18-4C10-4DCC-ABE6-15699EBB7C24
EOF

cat > /tmp/recent_guids.txt << 'EOF'
61FD5B15-0CA8-42C4-A4D6-59B542BD7EA9
E5D70363-94D8-453C-8E1A-67D9AB289F87
EOF

date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

echo "Launching MedinTux Manager..."
launch_medintux_manager

take_screenshot /tmp/overdue_followup_start.png 2>/dev/null || true

echo "=== Setup Complete: overdue_followup_scheduling ==="
