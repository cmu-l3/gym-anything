#!/bin/bash
# Setup script for medical_correspondence_batch task
# Inserts clinical context data for 3 patients requiring different medical documents:
# - ROUX Celine: Diabetic with poor HbA1c needing endocrinology referral
# - FOURNIER Jacques: Work accident needing consolidation certificate
# - GAUTHIER Helene: Palpitations + cardiac risk needing cardiology referral

echo "=== Setting up medical_correspondence_batch ==="

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

echo "Setting up clinical context for 3 target patients..."

python3 << 'PYEOF'
import pymysql
import datetime

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

def get_guid(nom, prenom):
    cursor.execute(
        "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos=%s AND FchGnrl_Prenom=%s AND FchGnrl_Type='Dossier'",
        (nom, prenom)
    )
    row = cursor.fetchone()
    return row[0] if row else None

def delete_rubrics_by_type(guid, type_rub):
    """Delete existing rubrics of a given type for a patient."""
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
    """Insert a rubric (head + blob) for a patient."""
    if date_str is None:
        date_str = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    # Insert head
    cursor.execute(
        "INSERT INTO RubriquesHead (RbDate_IDDos, RbDate_TypeRub, RbDate_Date) VALUES (%s, %s, %s)",
        (guid, type_rub, date_str)
    )
    pk = cursor.lastrowid
    # Insert blob
    cursor.execute(
        "INSERT INTO RubriquesBlobs (RbDate_PrimKey, RbDate_DataRub) VALUES (%s, %s)",
        (pk, blob_content.encode('latin1', errors='replace'))
    )
    # Link
    cursor.execute(
        "UPDATE RubriquesHead SET RbDate_RefBlobs_PrimKey=%s WHERE RbDate_PrimKey=%s",
        (pk, pk)
    )
    return pk

# ========== ROUX Celine: Diabetic patient needing endocrinology referral ==========
guid_roux = get_guid('ROUX', 'Celine')
if not guid_roux:
    # Try with accent
    guid_roux = get_guid('ROUX', 'C\xe9line')
if guid_roux:
    print(f"Found ROUX Celine GUID: {guid_roux}")
    # Clean and re-insert clinical context (terrain TypeRub=20060000)
    deleted = delete_rubrics_by_type(guid_roux, 20060000)
    if deleted:
        print(f"  Deleted {deleted} existing terrain rubric(s) for ROUX Celine")

    terrain_blob = (
        "[Antecedents]\n"
        "   DIABETE TYPE 2 = Maladie , Actif , E11 ,  ,  , \n"
        "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
        "   OBESITE = Maladie , Actif , E66 ,  ,  , \n"
    )
    insert_rubric(guid_roux, 20060000, terrain_blob, '2025-06-01 10:00:00')

    # Insert biology result with HbA1c 9.2% (TypeRub=20080000)
    deleted = delete_rubrics_by_type(guid_roux, 20080000)
    bio_blob = (
        "<html><head><title>Biologie</title></head><body>"
        "<p><b>Resultats biologie - 2026-01-10</b></p>"
        "<p>HbA1c : 9.2 % (N &lt; 7.0%) - ELEVE</p>"
        "<p>Glycemie a jeun : 11.4 mmol/L - ELEVE</p>"
        "<p>Creatinine : 82 umol/L</p>"
        "<p>Retinopathie diabetique : Depistage en retard (dernier controle 2024-03)</p>"
        "</body></html>"
    )
    insert_rubric(guid_roux, 20080000, bio_blob, '2026-01-10 09:00:00')
    print("  Inserted HbA1c biology result for ROUX Celine")

    # Delete any existing letters/certificates to ensure clean state
    for t in [20020500, 90010000, 20020300]:
        delete_rubrics_by_type(guid_roux, t)
else:
    print("WARNING: ROUX Celine not found in database!")

# ========== FOURNIER Jacques: Work accident needing consolidation certificate ==========
guid_fournier = get_guid('FOURNIER', 'Jacques')
if guid_fournier:
    print(f"Found FOURNIER Jacques GUID: {guid_fournier}")
    # Set up work accident antecedent (TypeRub=20030000)
    deleted = delete_rubrics_by_type(guid_fournier, 20030000)
    if deleted:
        print(f"  Deleted {deleted} existing consultation rubric(s) for FOURNIER Jacques")

    consult_blob = (
        "<html><head><title>Consultation</title></head><body>"
        "<p><b>Consultation AT/MP - 2026-01-15</b></p>"
        "<p>Accident de travail : chute sur le lieu de travail.</p>"
        "<p>Entorse severe de la cheville droite avec rupture partielle du ligament lateral externe.</p>"
        "<p>Arret de travail prescrit du 2026-01-15.</p>"
        "<p>Radiographie : pas de fracture. Traitement : immobilisation attelle, antalgiques, kinesitherapie.</p>"
        "</body></html>"
    )
    insert_rubric(guid_fournier, 20030000, consult_blob, '2026-01-15 11:00:00')

    # Insert terrain
    deleted = delete_rubrics_by_type(guid_fournier, 20060000)
    terrain_blob = (
        "[Antecedents]\n"
        "   ARTHROSE GENOU BILATERAL = Maladie , Actif , M17 ,  ,  , \n"
        "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
    )
    insert_rubric(guid_fournier, 20060000, terrain_blob, '2025-03-01 10:00:00')

    # Delete any existing certificates
    for t in [20020300, 20020500, 90010000]:
        delete_rubrics_by_type(guid_fournier, t)
    print("  Inserted work accident consultation for FOURNIER Jacques")
else:
    print("WARNING: FOURNIER Jacques not found in database!")

# ========== GAUTHIER Helene: Palpitations + cardiac risk needing cardiology referral ==========
guid_gauthier = get_guid('GAUTHIER', 'Helene')
if not guid_gauthier:
    guid_gauthier = get_guid('GAUTHIER', 'H\xe9l\xe8ne')
if guid_gauthier:
    print(f"Found GAUTHIER Helene GUID: {guid_gauthier}")
    # Set up terrain with cardiac risk factors
    deleted = delete_rubrics_by_type(guid_gauthier, 20060000)
    terrain_blob = (
        "[Antecedents]\n"
        "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
        "   ANTECEDENT FAMILIAL ARYTHMIE CARDIAQUE = Antecedent , Antecedent , Z82.4 ,  ,  , \n"
        "   TABAC = FdR , Actif , Z87.8 ,  ,  , \n"
    )
    insert_rubric(guid_gauthier, 20060000, terrain_blob, '2025-09-01 10:00:00')

    # Insert consultation documenting the palpitations
    deleted = delete_rubrics_by_type(guid_gauthier, 20030000)
    consult_blob = (
        "<html><head><title>Consultation</title></head><body>"
        "<p><b>Consultation - 2026-02-20</b></p>"
        "<p>Motif : Palpitations.</p>"
        "<p>La patiente decrit 2 a 3 episodes par semaine depuis environ 1 mois, durant 5 a 10 minutes.</p>"
        "<p>Pas de lipothymie ni syncope. Pas de douleur thoracique associee.</p>"
        "<p>ECG en cabinet : rythme sinusal, pas d'anomalie evidente.</p>"
        "<p>Antecedent familial : pere decede d'une arythmie cardiaque a 58 ans.</p>"
        "<p>Tension : 145/88 mmHg. FC : 72 bpm.</p>"
        "<p>Decision : adresser au cardiologue pour Holter ECG et bilan specialise.</p>"
        "</body></html>"
    )
    insert_rubric(guid_gauthier, 20030000, consult_blob, '2026-02-20 14:30:00')

    # Delete any existing letters
    for t in [20020500, 90010000, 20020300]:
        delete_rubrics_by_type(guid_gauthier, t)
    print("  Inserted palpitations consultation for GAUTHIER Helene")
else:
    print("WARNING: GAUTHIER Helene not found in database!")

conn.commit()
conn.close()
print("Clinical context setup complete.")
PYEOF

# Record baseline: store current max PrimKey in RubriquesHead for each patient
echo "Recording baseline document counts..."
python3 << 'PYEOF2'
import pymysql
import json

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

def get_guid(nom, prenom):
    cursor.execute(
        "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos=%s AND FchGnrl_Prenom=%s AND FchGnrl_Type='Dossier'",
        (nom, prenom)
    )
    row = cursor.fetchone()
    return row[0] if row else None

# Try both accented and unaccented versions
guid_roux = get_guid('ROUX', 'Celine') or get_guid('ROUX', 'C\xe9line')
guid_fournier = get_guid('FOURNIER', 'Jacques')
guid_gauthier = get_guid('GAUTHIER', 'Helene') or get_guid('GAUTHIER', 'H\xe9l\xe8ne')

# Get global max PrimKey in RubriquesHead (any new rubric after this = new document)
cursor.execute("SELECT COALESCE(MAX(RbDate_PrimKey), 0) FROM RubriquesHead")
max_pk = cursor.fetchone()[0]

baseline = {
    'max_rubrique_pk': int(max_pk),
    'guid_roux': guid_roux,
    'guid_fournier': guid_fournier,
    'guid_gauthier': guid_gauthier,
}
conn.close()

with open('/tmp/correspondence_baseline.json', 'w') as f:
    json.dump(baseline, f)

print(f"Baseline max RubriquesHead PK: {max_pk}")
print(f"ROUX GUID: {guid_roux}")
print(f"FOURNIER GUID: {guid_fournier}")
print(f"GAUTHIER GUID: {guid_gauthier}")
PYEOF2

date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

echo "Launching MedinTux Manager..."
launch_medintux_manager

take_screenshot /tmp/correspondence_start.png 2>/dev/null || true

echo "=== Setup Complete: medical_correspondence_batch ==="
