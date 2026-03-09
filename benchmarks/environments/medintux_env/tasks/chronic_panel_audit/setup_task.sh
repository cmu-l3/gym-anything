#!/bin/bash
# Setup script for chronic_panel_audit task
# Plants 4 clinical management gaps across 4 different patients:
# 1. DUBOIS Marie-Claire: HTA + T2DM in terrain, no prescription
# 2. LAMBERT Anne: Atrial fibrillation with only aspirin (no anticoagulant)
# 3. PERRIN Martine: COPD with last follow-up 2025-05-15 (overdue)
# 4. NICOLAS Sandrine: Migraine with aura + combined OCP (contraindicated)

echo "=== Setting up chronic_panel_audit ==="

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

echo "Planting clinical issues for audit task..."

python3 << 'PYEOF'
import pymysql
import datetime

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

def get_guid(nom, prenom_variants):
    """Try multiple prenom variants to find the patient."""
    for prenom in prenom_variants:
        cursor.execute(
            "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos=%s AND FchGnrl_Prenom=%s AND FchGnrl_Type='Dossier'",
            (nom, prenom)
        )
        row = cursor.fetchone()
        if row:
            return row[0]
    return None

def delete_rubrics_of_type(guid, type_rub):
    cursor.execute(
        "SELECT RbDate_PrimKey FROM RubriquesHead WHERE RbDate_IDDos=%s AND RbDate_TypeRub=%s",
        (guid, type_rub)
    )
    pks = [row[0] for row in cursor.fetchall()]
    for pk in pks:
        cursor.execute("DELETE FROM RubriquesBlobs WHERE RbDate_PrimKey=%s", (pk,))
        cursor.execute("DELETE FROM RubriquesHead WHERE RbDate_PrimKey=%s", (pk,))
    return len(pks)

def insert_rubric(guid, type_rub, blob_content, date_str=None):
    if date_str is None:
        date_str = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    cursor.execute(
        "INSERT INTO RubriquesHead (RbDate_IDDos, RbDate_TypeRub, RbDate_Date) VALUES (%s, %s, %s)",
        (guid, type_rub, date_str)
    )
    pk = cursor.lastrowid
    cursor.execute(
        "INSERT INTO RubriquesBlobs (RbDate_PrimKey, RbDate_DataRub) VALUES (%s, %s)",
        (pk, blob_content.encode('latin1', errors='replace'))
    )
    cursor.execute(
        "UPDATE RubriquesHead SET RbDate_RefBlobs_PrimKey=%s WHERE RbDate_PrimKey=%s",
        (pk, pk)
    )
    return pk

def delete_agenda_for_guid(guid):
    cursor.execute("DELETE FROM agenda WHERE GUID=%s", (guid,))

# ========== Issue 1: DUBOIS Marie-Claire ==========
# HTA + T2DM documented, but NO prescription
guid_dubois = get_guid('DUBOIS', ['Marie-Claire', 'Marie Claire', 'MARIE-CLAIRE'])
if guid_dubois:
    print(f"DUBOIS Marie-Claire GUID: {guid_dubois}")
    # Clear all clinical rubrics for clean state
    for t in [20060000, 20030000, 20020100]:
        n = delete_rubrics_of_type(guid_dubois, t)
        if n:
            print(f"  Deleted {n} rubrics of type {t}")

    # Plant terrain: HTA + T2DM (but intentionally NO prescription)
    terrain_blob = (
        "[Antecedents]\n"
        "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
        "   DIABETE TYPE 2 = Maladie , Actif , E11 ,  ,  , \n"
        "   OBESITE = FdR , Actif , E66 ,  ,  , \n"
    )
    insert_rubric(guid_dubois, 20060000, terrain_blob, '2025-04-01 10:00:00')

    # Plant an old consultation note confirming diagnosis
    consult_blob = (
        "<html><head><title>Consultation</title></head><body>"
        "<p>Consultation 2025-04-01 : Controle annuel.</p>"
        "<p>HbA1c 8.1%. Tension 158/96 mmHg.</p>"
        "<p>Diagnostic : HTA moderee non controlee. Diabete type 2 non equilibre.</p>"
        "<p>Traitement a initier.</p>"
        "</body></html>"
    )
    insert_rubric(guid_dubois, 20030000, consult_blob, '2025-04-01 10:00:00')
    print("  Planted: HTA+T2DM terrain with no prescription for DUBOIS Marie-Claire")
else:
    print("WARNING: DUBOIS Marie-Claire not found!")

# ========== Issue 2: LAMBERT Anne ==========
# Atrial fibrillation documented + only aspirin prescribed (should have anticoagulant)
guid_lambert = get_guid('LAMBERT', ['Anne', 'ANNE'])
if guid_lambert:
    print(f"LAMBERT Anne GUID: {guid_lambert}")
    for t in [20060000, 20030000, 20020100]:
        n = delete_rubrics_of_type(guid_lambert, t)
        if n:
            print(f"  Deleted {n} rubrics of type {t}")

    # Plant terrain: Fibrillation auriculaire + valvular disease
    terrain_blob = (
        "[Antecedents]\n"
        "   FIBRILLATION AURICULAIRE = Maladie , Actif , I48 ,  ,  , \n"
        "   INSUFFISANCE CARDIAQUE = Maladie , Actif , I50 ,  ,  , \n"
        "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
    )
    insert_rubric(guid_lambert, 20060000, terrain_blob, '2025-03-15 09:00:00')

    # Plant WRONG prescription: aspirin only (no anticoagulant)
    presc_blob = (
        '<?xml version="1.0" encoding="ISO-8859-1"?>'
        '<ordotext><html><head><title>Ordonnance</title></head><body>'
        '<p>ASPIRINE CARDIO 100mg : 1 comprime par jour</p>'
        '<p>BISOPROLOL 2.5mg : 1 comprime le matin</p>'
        '<p>RAMIPRIL 5mg : 1 comprime le matin</p>'
        '</body></html></ordotext>'
    )
    insert_rubric(guid_lambert, 20020100, presc_blob, '2025-03-15 09:00:00')

    # Consultation note documenting the AF diagnosis
    consult_blob = (
        "<html><head><title>Consultation</title></head><body>"
        "<p>Consultation 2025-03-15 : Bilan cardiologique.</p>"
        "<p>Fibrillation auriculaire permanente diagnostiquee. ECG confirme.</p>"
        "<p>Score CHA2DS2-VASc : 4 (FA + HTA + age + IC). Anticoagulation indiquee.</p>"
        "<p>Traitement en cours revu.</p>"
        "</body></html>"
    )
    insert_rubric(guid_lambert, 20030000, consult_blob, '2025-03-15 09:00:00')
    print("  Planted: AF with aspirin-only prescription for LAMBERT Anne")
else:
    print("WARNING: LAMBERT Anne not found!")

# ========== Issue 3: PERRIN Martine ==========
# COPD with last follow-up 2025-05-15 — no recent agenda entry
guid_perrin = get_guid('PERRIN', ['Martine', 'MARTINE'])
if guid_perrin:
    print(f"PERRIN Martine GUID: {guid_perrin}")
    for t in [20060000, 20030000, 20020100]:
        n = delete_rubrics_of_type(guid_perrin, t)
        if n:
            print(f"  Deleted {n} rubrics of type {t}")
    # Remove all agenda entries for this patient
    delete_agenda_for_guid(guid_perrin)

    # Plant terrain: BPCO (COPD)
    terrain_blob = (
        "[Antecedents]\n"
        "   BPCO = Maladie , Actif , J44 ,  ,  , \n"
        "   TABAGISME SEVRAGE = Antecedent , Actif , Z87.8 ,  ,  , \n"
        "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
    )
    insert_rubric(guid_perrin, 20060000, terrain_blob, '2024-10-01 10:00:00')

    # Plant last consultation as 2025-05-15 (over 9 months ago from 2026-03-02)
    consult_blob = (
        "<html><head><title>Consultation</title></head><body>"
        "<p>Consultation 2025-05-15 : Suivi BPCO.</p>"
        "<p>EFR stable, VEMS 58% theorique. Pas d'exacerbation depuis 6 mois.</p>"
        "<p>Traitement maintenu. Rappel pour suivi dans 6 mois.</p>"
        "</body></html>"
    )
    insert_rubric(guid_perrin, 20030000, consult_blob, '2025-05-15 11:00:00')

    # Plant active prescription for COPD
    presc_blob = (
        '<?xml version="1.0" encoding="ISO-8859-1"?>'
        '<ordotext><html><head><title>Ordonnance</title></head><body>'
        '<p>TIOTROPIUM (SPIRIVA) 18 microg : 1 inhalation par jour</p>'
        '<p>SALBUTAMOL spray : en cas de besoin</p>'
        '<p>AMLODIPINE 5mg : 1 comprime le soir</p>'
        '</body></html></ordotext>'
    )
    insert_rubric(guid_perrin, 20020100, presc_blob, '2025-05-15 11:00:00')
    print("  Planted: COPD patient overdue for follow-up for PERRIN Martine")
else:
    print("WARNING: PERRIN Martine not found!")

# ========== Issue 4: NICOLAS Sandrine ==========
# Migraine with aura + combined OCP (absolute contraindication)
guid_nicolas = get_guid('NICOLAS', ['Sandrine', 'SANDRINE'])
if guid_nicolas:
    print(f"NICOLAS Sandrine GUID: {guid_nicolas}")
    for t in [20060000, 20030000, 20020100]:
        n = delete_rubrics_of_type(guid_nicolas, t)
        if n:
            print(f"  Deleted {n} rubrics of type {t}")

    # Plant terrain: Migraine avec aura
    terrain_blob = (
        "[Antecedents]\n"
        "   MIGRAINE AVEC AURA = Maladie , Actif , G43.1 ,  ,  , \n"
        "   TABAGISME = FdR , Actif , Z87.8 ,  ,  , \n"
    )
    insert_rubric(guid_nicolas, 20060000, terrain_blob, '2025-01-20 09:00:00')

    # Plant prescription with combined OCP (contraindicated with migraine with aura)
    presc_blob = (
        '<?xml version="1.0" encoding="ISO-8859-1"?>'
        '<ordotext><html><head><title>Ordonnance</title></head><body>'
        '<p>ETHINYLESTRADIOL / LEVONORGESTREL (LUDEAL) : 1 comprime par jour du J1 au J21</p>'
        '<p>SUMATRIPTAN 50mg : en cas de crise migraineuse (max 2/jour)</p>'
        '<p>DOLIPRANE 1g : si douleur</p>'
        '</body></html></ordotext>'
    )
    insert_rubric(guid_nicolas, 20020100, presc_blob, '2025-01-20 09:00:00')

    # Consultation noting the migraine
    consult_blob = (
        "<html><head><title>Consultation</title></head><body>"
        "<p>Consultation 2025-01-20 : Renouvellement contraception.</p>"
        "<p>Migraines avec aura documentees depuis 2023.</p>"
        "<p>Patiente satisfaite de sa contraception actuelle.</p>"
        "</body></html>"
    )
    insert_rubric(guid_nicolas, 20030000, consult_blob, '2025-01-20 09:00:00')
    print("  Planted: Migraine avec aura + combined OCP for NICOLAS Sandrine")
else:
    print("WARNING: NICOLAS Sandrine not found!")

conn.commit()
conn.close()
print("\nAll clinical issues planted successfully.")
PYEOF

# Record baseline state
echo "Recording baseline state..."
python3 << 'PYEOF2'
import pymysql
import json

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

def get_guid(nom, prenom_variants):
    for prenom in prenom_variants:
        cursor.execute(
            "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos=%s AND FchGnrl_Prenom=%s AND FchGnrl_Type='Dossier'",
            (nom, prenom)
        )
        row = cursor.fetchone()
        if row:
            return row[0]
    return None

guid_dubois = get_guid('DUBOIS', ['Marie-Claire', 'Marie Claire'])
guid_lambert = get_guid('LAMBERT', ['Anne'])
guid_perrin = get_guid('PERRIN', ['Martine'])
guid_nicolas = get_guid('NICOLAS', ['Sandrine'])

# Max PrimKey in RubriquesHead (any rubric created after this = new work)
cursor.execute("SELECT COALESCE(MAX(RbDate_PrimKey), 0) FROM RubriquesHead")
max_rubrique_pk = cursor.fetchone()[0]

# Max PrimKey in agenda (any agenda entry created after this = new appointment)
cursor.execute("SELECT COALESCE(MAX(PrimKey), 0) FROM agenda")
max_agenda_pk = cursor.fetchone()[0]

baseline = {
    'max_rubrique_pk': int(max_rubrique_pk),
    'max_agenda_pk': int(max_agenda_pk),
    'guid_dubois': guid_dubois,
    'guid_lambert': guid_lambert,
    'guid_perrin': guid_perrin,
    'guid_nicolas': guid_nicolas,
}
conn.close()

with open('/tmp/audit_baseline.json', 'w') as f:
    json.dump(baseline, f)

print(f"Baseline: max_rubrique_pk={max_rubrique_pk}, max_agenda_pk={max_agenda_pk}")
print(f"Patient GUIDs: DUBOIS={guid_dubois}, LAMBERT={guid_lambert}, PERRIN={guid_perrin}, NICOLAS={guid_nicolas}")
PYEOF2

date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

echo "Launching MedinTux Manager..."
launch_medintux_manager

take_screenshot /tmp/audit_start.png 2>/dev/null || true

echo "=== Setup Complete: chronic_panel_audit ==="
