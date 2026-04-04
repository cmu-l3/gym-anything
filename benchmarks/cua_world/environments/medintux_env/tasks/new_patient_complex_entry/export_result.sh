#!/bin/bash
# Export script for new_patient_complex_entry task
# Queries whether BONNET Elise was created with all required components

echo "=== Exporting new_patient_complex_entry Result ==="

source /workspace/scripts/task_utils.sh

if ! type medintux_query &>/dev/null; then
    medintux_query() { mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

take_screenshot /tmp/new_patient_complex_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_DT=$(date -d "@${TASK_START}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-01-01 00:00:00")
BASELINE_PATIENTS=$(cat /tmp/baseline_patient_count 2>/dev/null || echo "0")
BASELINE_AGENDA_PK=$(cat /tmp/baseline_agenda_pk 2>/dev/null || echo "0")

echo "Task started at: $TASK_START_DT"
echo "Baseline patient count: $BASELINE_PATIENTS"
echo "Baseline agenda max PrimKey: $BASELINE_AGENDA_PK"

python3 << PYEOF > /tmp/new_patient_result.json
import pymysql
import json

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

task_start_dt = '${TASK_START_DT}'
baseline_agenda_pk = int('${BASELINE_AGENDA_PK}' or 0)

result = {
    "task_start": ${TASK_START},
    "task_start_dt": task_start_dt,
    "baseline_patients": ${BASELINE_PATIENTS},
    "baseline_agenda_pk": baseline_agenda_pk,
    "patient_created": False,
    "patient_guid": None,
    "demographics_ok": False,
    "has_terrain_rubric": False,
    "terrain_has_aspirine_allergy": False,
    "has_consultation_rubric": False,
    "consultation_has_hypertension": False,
    "consultation_has_hypothyroidie": False,
    "has_prescription_rubric": False,
    "prescription_has_ramipril": False,
    "prescription_has_levothyroxine": False,
    "prescription_has_amlodipine": False,
    "has_agenda_entry": False,
    "agenda_date_correct": False,
}

# Check patient exists in IndexNomPrenom
cursor.execute(
    "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='BONNET' AND FchGnrl_Prenom='Elise' AND FchGnrl_Type='Dossier'"
)
rows = cursor.fetchall()
if not rows:
    conn.close()
    print(json.dumps(result))
    exit()

guid = rows[0][0]
result["patient_created"] = True
result["patient_guid"] = guid

# Check demographics in fchpat
cursor.execute(
    "SELECT FchPat_Nee, FchPat_Sexe, FchPat_CP, FchPat_Ville FROM fchpat WHERE FchPat_GUID_Doss=%s",
    (guid,)
)
dem = cursor.fetchone()
if dem:
    dob_str = str(dem[0]) if dem[0] else ''
    sex = str(dem[1]) if dem[1] else ''
    cp = str(dem[2]) if dem[2] else ''
    ville = str(dem[3]).upper() if dem[3] else ''
    dob_ok = '1958-04-12' in dob_str or '19580412' in dob_str.replace('-','').replace('/','')
    sex_ok = sex.upper() in ('F', 'FEMME', '2', 'W')
    cp_ok = '38' in cp  # Grenoble is 38000-38999
    ville_ok = 'GRENOBLE' in ville
    result["demographics_ok"] = dob_ok and (sex_ok or cp_ok or ville_ok)

# Check terrain rubric (TypeRub=20060000)
cursor.execute("""
    SELECT rh.RbDate_PrimKey, CONVERT(rb.RbDate_DataRub USING utf8)
    FROM RubriquesHead rh
    LEFT JOIN RubriquesBlobs rb ON rh.RbDate_PrimKey = rb.RbDate_PrimKey
    WHERE rh.RbDate_IDDos=%s AND rh.RbDate_TypeRub=20060000
    ORDER BY rh.RbDate_Date DESC LIMIT 1
""", (guid,))
terrain_row = cursor.fetchone()
if terrain_row:
    result["has_terrain_rubric"] = True
    content = (terrain_row[1] or '').lower()
    result["terrain_has_aspirine_allergy"] = 'aspirine' in content or 'aspirin' in content or 'asa' in content

# Check consultation rubric (TypeRub=20030000) - antecedents/history
cursor.execute("""
    SELECT rh.RbDate_PrimKey, CONVERT(rb.RbDate_DataRub USING utf8)
    FROM RubriquesHead rh
    LEFT JOIN RubriquesBlobs rb ON rh.RbDate_PrimKey = rb.RbDate_PrimKey
    WHERE rh.RbDate_IDDos=%s AND rh.RbDate_TypeRub=20030000
    ORDER BY rh.RbDate_Date DESC LIMIT 1
""", (guid,))
cons_row = cursor.fetchone()
if cons_row:
    result["has_consultation_rubric"] = True
    content = (cons_row[1] or '').lower()
    result["consultation_has_hypertension"] = 'hypertension' in content or 'hta' in content
    result["consultation_has_hypothyroidie"] = 'hypothyro' in content or 'thyro' in content or 'levothyrox' in content

# Check prescription rubric (TypeRub=20020100)
cursor.execute("""
    SELECT rh.RbDate_PrimKey, CONVERT(rb.RbDate_DataRub USING utf8)
    FROM RubriquesHead rh
    LEFT JOIN RubriquesBlobs rb ON rh.RbDate_PrimKey = rb.RbDate_PrimKey
    WHERE rh.RbDate_IDDos=%s AND rh.RbDate_TypeRub=20020100
    ORDER BY rh.RbDate_Date DESC LIMIT 1
""", (guid,))
presc_row = cursor.fetchone()
if presc_row:
    result["has_prescription_rubric"] = True
    content = (presc_row[1] or '').lower()
    result["prescription_has_ramipril"] = 'ramipril' in content
    result["prescription_has_levothyroxine"] = 'levothyroxine' in content or 'levothyrox' in content
    result["prescription_has_amlodipine"] = 'amlodipine' in content or 'amlor' in content

# Check agenda entry after task start
cursor.execute("""
    SELECT PrimKey, Date_Time, Nom, Prenom, Note
    FROM agenda
    WHERE (GUID=%s OR (Nom='BONNET' AND Prenom='Elise'))
    AND PrimKey > %s
    ORDER BY Date_Time ASC
""", (guid, baseline_agenda_pk))
agenda_rows = cursor.fetchall()
if agenda_rows:
    result["has_agenda_entry"] = True
    for row in agenda_rows:
        dt_str = str(row[1]) if row[1] else ''
        if '2026-04-02' in dt_str or '20260402' in dt_str.replace('-',''):
            result["agenda_date_correct"] = True
            break

conn.close()
print(json.dumps(result, ensure_ascii=False))
PYEOF

echo "Result saved to /tmp/new_patient_result.json"
cat /tmp/new_patient_result.json
echo ""
echo "=== Export Complete ==="
