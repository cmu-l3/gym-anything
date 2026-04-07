#!/bin/bash
# setup_task.sh — Pharmacovigilance Alert Response
# Seeds 4 patients with Metformine prescriptions, each with different DFG levels
# and clinical contexts. Places the CRPV alert document on the Desktop.

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type medintux_query &>/dev/null; then
    medintux_query() { mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

# Kill any running MedinTux/Wine
pkill -f Manager.exe 2>/dev/null || true
pkill -f wine 2>/dev/null || true
sleep 3

# Start MySQL
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Verify target patients exist
GUID_DUBOIS=$(medintux_query "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUBOIS' AND FchGnrl_Prenom='Marie-Claire' AND FchGnrl_Type='Dossier';")
GUID_MARTIN=$(medintux_query "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='MARTIN' AND FchGnrl_Prenom='Sophie' AND FchGnrl_Type='Dossier';")
GUID_PETIT=$(medintux_query "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='PETIT' AND FchGnrl_Prenom='Nathalie' AND FchGnrl_Type='Dossier';")
GUID_HENRY=$(medintux_query "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='HENRY' AND FchGnrl_Prenom='Emmanuel' AND FchGnrl_Type='Dossier';")

for PNAME in DUBOIS MARTIN PETIT HENRY; do
    GUID_VAR="GUID_${PNAME}"
    if [ -z "${!GUID_VAR}" ]; then
        echo "ERROR: Patient ${PNAME} not found in database"
        exit 1
    fi
    echo "Found ${PNAME}: ${!GUID_VAR}"
done

# Delete any prior report file BEFORE recording timestamp
rm -f /home/ga/Documents/rapport_pharmacovigilance_CRPV-2026-0847.csv

# Clean existing rubrics and agenda for target patients, then seed fresh data
python3 << 'PYEOF'
import pymysql
import json
import sys

conn = pymysql.connect(host='localhost', user='root', database='DrTuxTest', charset='latin1')
cursor = conn.cursor()

# --- Helper functions ---

def get_guid(nom, prenom):
    cursor.execute(
        "SELECT FchGnrl_IDDos FROM IndexNomPrenom "
        "WHERE FchGnrl_NomDos=%s AND FchGnrl_Prenom=%s AND FchGnrl_Type='Dossier'",
        (nom, prenom))
    row = cursor.fetchone()
    return row[0] if row else None

def get_refpk(guid):
    cursor.execute("SELECT FchPat_RefPk FROM fchpat WHERE FchPat_GUID_Doss=%s", (guid,))
    row = cursor.fetchone()
    return row[0] if row else 0

def insert_rubric(guid, type_rub, date_str, blob_content, nom_date='', sub_type='Default SubType'):
    refpk = get_refpk(guid)
    cursor.execute(
        """INSERT INTO RubriquesHead
           (RbDate_IDDos, RbDate_TypeRub, RbDate_NomDate, RbDate_SubTypeRub,
            RbDate_Date, RbDate_CreateUser, RbDate_Ref_NumDoss)
           VALUES (%s, %s, %s, %s, %s, 'admin', %s)""",
        (guid, type_rub, nom_date, sub_type, date_str, refpk))
    pk = cursor.lastrowid
    cursor.execute(
        "INSERT INTO RubriquesBlobs (RbDate_PrimKey, RbDate_DataRub, RbDate_IDDos) "
        "VALUES (%s, %s, %s)",
        (pk, blob_content.encode('latin1', errors='replace'), guid))
    cursor.execute(
        "UPDATE RubriquesHead SET RbDate_RefBlobs_PrimKey=%s WHERE RbDate_PrimKey=%s",
        (pk, pk))
    return pk

# --- Lookup GUIDs ---

patients = {
    'DUBOIS': get_guid('DUBOIS', 'Marie-Claire'),
    'MARTIN': get_guid('MARTIN', 'Sophie'),
    'PETIT':  get_guid('PETIT', 'Nathalie'),
    'HENRY':  get_guid('HENRY', 'Emmanuel'),
}

for name, guid in patients.items():
    if not guid:
        print(f"ERROR: {name} GUID not found", file=sys.stderr)
        sys.exit(1)

guids = list(patients.values())

# --- Clean existing rubrics and agenda for these 4 patients ---

placeholders = ','.join(['%s'] * len(guids))
cursor.execute(
    f"SELECT RbDate_PrimKey FROM RubriquesHead WHERE RbDate_IDDos IN ({placeholders})",
    guids)
pks = [r[0] for r in cursor.fetchall()]
if pks:
    pk_ph = ','.join(['%s'] * len(pks))
    cursor.execute(f"DELETE FROM RubriquesBlobs WHERE RbDate_PrimKey IN ({pk_ph})", pks)
    cursor.execute(f"DELETE FROM RubriquesHead WHERE RbDate_PrimKey IN ({pk_ph})", pks)

cursor.execute(f"DELETE FROM agenda WHERE GUID IN ({placeholders})", guids)
conn.commit()

# ===================================================================
# SEED CLINICAL DATA
# ===================================================================

# --- DUBOIS Marie-Claire (DFG 32, branch a -> Sitagliptine) ---
g = patients['DUBOIS']

# Terrain: HTA + T2DM + CKD 3b (no drug allergies)
insert_rubric(g, 20060000, '2024-01-10 10:00:00',
    "[Antecedents]\n"
    "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
    "   DIABETE TYPE 2 = Maladie , Actif , E11 ,  ,  , \n"
    "   INSUFFISANCE RENALE CHRONIQUE STADE 3B = Maladie , Actif , N18.3 ,  ,  , ",
    'Terrain')

# Current prescription with Metformine 850mg
insert_rubric(g, 20020100, '2025-12-01 09:00:00',
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>'
    '<ordotext>'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">'
    '<p>Ramipril 5mg cp : 1 comprime le matin</p>'
    '<p>Metformine 850mg cp : 1 comprime matin et soir</p>'
    '<p>Atorvastatine 20mg cp : 1 comprime le soir</p>'
    '</body></html>'
    '</ordotext>',
    'Ordonnance')

# OLD consultation (2025-06-15) with STALE DFG = 48 (temporal trap)
insert_rubric(g, 20030000, '2025-06-15 10:30:00',
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 15/06/2025 - Suivi nephro-diabetologique</p>'
    '<p>Bilan du 10/06/2025: creatinine 112 umol/L, DFG estime (CKD-EPI) = 48 ml/min/1.73m2.</p>'
    '<p>Fonction renale legerement alteree mais stable. Maintien traitement actuel.</p>'
    '<p>TA: 138/82. Poids: 71 kg.</p>'
    '</body></html>',
    'Consultation')

# RECENT consultation (2026-02-15) with CURRENT DFG = 32
insert_rubric(g, 20030000, '2026-02-15 14:00:00',
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 15/02/2026 - Suivi nephrologique</p>'
    '<p>Resultats bilan sanguin du 10/02/2026:</p>'
    '<p>Creatinine 148 umol/L, DFG estime (CKD-EPI) = 32 ml/min/1.73m2.</p>'
    '<p>Aggravation de la fonction renale. IRC stade 3b confirmee.</p>'
    '<p>TA: 142/85. Discussion adaptation therapeutique a prevoir.</p>'
    '</body></html>',
    'Consultation')


# --- MARTIN Sophie (DFG 55, branch b -> Metformine 500mg) ---
g = patients['MARTIN']

# Terrain: HTA + T2DM + Dyslipidemia
insert_rubric(g, 20060000, '2024-03-15 10:00:00',
    "[Antecedents]\n"
    "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
    "   DIABETE TYPE 2 = Maladie , Actif , E11 ,  ,  , \n"
    "   DYSLIPIDEMIE = Maladie , Actif , E78 ,  ,  , ",
    'Terrain')

# Current prescription with Metformine 850mg
insert_rubric(g, 20020100, '2025-11-20 09:00:00',
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>'
    '<ordotext>'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">'
    '<p>Amlodipine 5mg cp : 1 comprime le matin</p>'
    '<p>Metformine 850mg cp : 1 comprime matin et soir</p>'
    '<p>Simvastatine 20mg cp : 1 comprime le soir</p>'
    '</body></html>'
    '</ordotext>',
    'Ordonnance')

# Biologie (2026-01-20) with DFG = 55 in structured lab result
insert_rubric(g, 20080000, '2026-01-20 08:30:00',
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Bilan biologique du 20/01/2026</p>'
    '<p>Creatinine: 98 umol/L</p>'
    '<p>DFG (CKD-EPI): 55 ml/min/1.73m2</p>'
    '<p>HbA1c: 6.9%</p>'
    '<p>Glycemie a jeun: 1.12 g/L</p>'
    '</body></html>',
    'Biologie')


# --- PETIT Nathalie (DFG 92, branch c -> Glucophage 850mg) ---
g = patients['PETIT']

# Terrain: T2DM only
insert_rubric(g, 20060000, '2024-06-01 10:00:00',
    "[Antecedents]\n"
    "   DIABETE TYPE 2 = Maladie , Actif , E11 ,  ,  , ",
    'Terrain')

# Current prescription with Metformine 850mg (monotherapy)
insert_rubric(g, 20020100, '2025-10-15 09:00:00',
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>'
    '<ordotext>'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">'
    '<p>Metformine 850mg cp : 1 comprime matin et soir</p>'
    '</body></html>'
    '</ordotext>',
    'Ordonnance')

# Consultation (2026-02-28) with DFG = 92 embedded in narrative text
insert_rubric(g, 20030000, '2026-02-28 11:00:00',
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Consultation du 28/02/2026 - Controle diabetologique trimestriel</p>'
    '<p>Bon equilibre glycemique sous Metformine seule.</p>'
    '<p>Bilan sanguin recu: HbA1c 7.1%, creatinine normale 68 umol/L '
    'avec DFG CKD-EPI a 92 ml/min/1.73m2.</p>'
    '<p>Pas de complication micro ou macrovasculaire.</p>'
    '<p>TA: 125/78. Poids: 62 kg. IMC: 23.4.</p>'
    '</body></html>',
    'Consultation')


# --- HENRY Emmanuel (DFG 38, branch a + ALLERGY TRAP -> Repaglinide) ---
g = patients['HENRY']

# Terrain: T2DM + HTA + CKD 3b + GLIPTINE ALLERGY (the trap)
insert_rubric(g, 20060000, '2024-02-20 10:00:00',
    "[Antecedents]\n"
    "   DIABETE TYPE 2 = Maladie , Actif , E11 ,  ,  , \n"
    "   HYPERTENSION ARTERIELLE = Maladie , Actif , I10 ,  ,  , \n"
    "   INSUFFISANCE RENALE CHRONIQUE STADE 3B = Maladie , Actif , N18.3 ,  ,  , \n"
    "   GLIPTINES (DPP-4) = Allergique , Actif ,  ,  ,  , ",
    'Terrain')

# Current prescription with Metformine 850mg + insulin
insert_rubric(g, 20020100, '2025-12-10 09:00:00',
    '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes" ?>'
    '<ordotext>'
    '<html><head><meta name="qrichtext" content="1" /><title>Ordonnance</title></head>'
    '<body style="font-size:10pt;font-family:Arial">'
    '<p>Losartan 50mg cp : 1 comprime le matin</p>'
    '<p>Metformine 850mg cp : 1 comprime matin et soir</p>'
    '<p>Insuline Lantus : 20 UI injection sous-cutanee le soir</p>'
    '</body></html>'
    '</ordotext>',
    'Ordonnance')

# Biologie (2026-03-01) with DFG = 38
insert_rubric(g, 20080000, '2026-03-01 08:00:00',
    '<html><head><meta name="qrichtext" content="1" /></head>'
    '<body style="font-size:9pt;font-family:MS Shell Dlg">'
    '<p>Bilan biologique du 01/03/2026</p>'
    '<p>Creatinine: 165 umol/L</p>'
    '<p>DFG (CKD-EPI): 38 ml/min/1.73m2</p>'
    '<p>HbA1c: 8.2%</p>'
    '<p>Kaliemie: 4.8 mmol/L</p>'
    '<p>Glycemie a jeun: 1.65 g/L</p>'
    '</body></html>',
    'Biologie')

conn.commit()

# ===================================================================
# RECORD BASELINE (after all seeded data is committed)
# ===================================================================

cursor.execute("SELECT COALESCE(MAX(RbDate_PrimKey), 0) FROM RubriquesHead")
max_rub_pk = cursor.fetchone()[0]
cursor.execute("SELECT COALESCE(MAX(PrimKey), 0) FROM agenda")
max_agenda_pk = cursor.fetchone()[0]

baseline = {
    'max_rubrique_pk': int(max_rub_pk),
    'max_agenda_pk': int(max_agenda_pk),
    'patient_guids': {name: guid for name, guid in patients.items()}
}
with open('/tmp/pharma_alert_baseline.json', 'w') as f:
    json.dump(baseline, f)

print(f"Baseline recorded: max_rub_pk={max_rub_pk}, max_agenda_pk={max_agenda_pk}")
for name, guid in patients.items():
    print(f"  {name}: {guid}")

cursor.close()
conn.close()
PYEOF

# ===================================================================
# WRITE THE ALERT DOCUMENT
# ===================================================================

mkdir -p /home/ga/Documents

cat > /home/ga/Documents/alerte_pharmacovigilance_metformine.txt << 'ALERTEOF'
CENTRE REGIONAL DE PHARMACOVIGILANCE
ALERTE DE SECURITE N. CRPV-2026-0847

Date : 20 mars 2026
Objet : Contamination NDMA - Metformine 850mg lot LOT-2024-M892

Le CRPV informe les prescripteurs qu'une contamination par NDMA
(N-nitrosodimethylamine) superieure aux seuils reglementaires a ete
detectee dans le lot LOT-2024-M892 de Metformine 850mg
(fabricant: PharmLab SA).

ACTIONS REQUISES POUR CHAQUE PATIENT SOUS METFORMINE 850mg :

1. Evaluer la fonction renale du patient (DFG/eGFR le plus recent
   dans le dossier clinique).

2. Appliquer l'algorithme de substitution suivant :

   a) DFG < 45 ml/min :
      ARRET de la Metformine.
      Substituer par Sitagliptine 50mg, 1 comprime par jour
      (dose ajustee pour insuffisance renale).
      En cas d'allergie documentee aux gliptines :
      substituer par Repaglinide 1mg, 1 comprime avant
      chaque repas principal (3 fois par jour).

   b) DFG entre 45 et 60 ml/min :
      REDUCTION de dose.
      Passer de Metformine 850mg a Metformine 500mg,
      meme posologie (nombre de prises inchange).

   c) DFG > 60 ml/min :
      CHANGEMENT de fabricant.
      Remplacer par Glucophage 850mg (fabricant: Merck Sante),
      meme posologie.

3. Pour tout changement de classe medicamenteuse (cas a uniquement),
   prevoir un rendez-vous de controle dans les 15 jours pour evaluer
   la tolerance du nouveau traitement.

4. Documenter chaque modification dans le dossier patient avec
   la mention "Alerte CRPV-2026-0847" et le motif clinique.

Contact : Dr. Marie LECLERC, CRPV Rhone-Alpes
Tel : 04 72 11 69 97
ALERTEOF

chown ga:ga /home/ga/Documents/alerte_pharmacovigilance_metformine.txt

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch MedinTux
launch_medintux_manager

take_screenshot /tmp/pharma_alert_start.png 2>/dev/null || true

echo "Setup complete: pharmacovigilance_alert_response"
