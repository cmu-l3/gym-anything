#!/bin/bash
# Export script for chronic_panel_audit task
# Checks what corrective actions were taken for each of the 4 issue patients

echo "=== Exporting chronic_panel_audit Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

take_screenshot /tmp/audit_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_DT=$(date -d "@${TASK_START}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-01-01 00:00:00")

python3 << PYEOF > /tmp/audit_result.json
import pymysql
import json

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

# Load baseline
try:
    with open('/tmp/audit_baseline.json') as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

max_rubrique_pk = baseline.get('max_rubrique_pk', 0)
max_agenda_pk = baseline.get('max_agenda_pk', 0)

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

guid_dubois = baseline.get('guid_dubois') or get_guid('DUBOIS', ['Marie-Claire', 'Marie Claire'])
guid_lambert = baseline.get('guid_lambert') or get_guid('LAMBERT', ['Anne'])
guid_perrin = baseline.get('guid_perrin') or get_guid('PERRIN', ['Martine'])
guid_nicolas = baseline.get('guid_nicolas') or get_guid('NICOLAS', ['Sandrine'])

def get_new_rubrics(guid, type_rub):
    if not guid:
        return []
    cursor.execute("""
        SELECT rh.RbDate_PrimKey, rh.RbDate_Date,
               CONVERT(rb.RbDate_DataRub USING utf8)
        FROM RubriquesHead rh
        LEFT JOIN RubriquesBlobs rb ON rh.RbDate_PrimKey = rb.RbDate_PrimKey
        WHERE rh.RbDate_IDDos=%s AND rh.RbDate_TypeRub=%s
          AND rh.RbDate_PrimKey > %s
        ORDER BY rh.RbDate_Date DESC
    """, (guid, type_rub, max_rubrique_pk))
    return cursor.fetchall()

def content_has(content, keywords):
    c = (content or '').lower()
    return [kw for kw in keywords if kw.lower() in c]

result = {
    "task_start": ${TASK_START},
    "task_start_dt": '${TASK_START_DT}',
    "baseline_rubrique_pk": max_rubrique_pk,
    "baseline_agenda_pk": max_agenda_pk,

    # Issue 1: DUBOIS — new prescription needed
    "dubois": {
        "guid": guid_dubois,
        "has_new_prescription": False,
        "prescription_has_antihypertensive": False,
        "prescription_has_antidiabetic": False,
        "has_new_consultation_note": False,
    },
    # Issue 2: LAMBERT — anticoagulant needed
    "lambert": {
        "guid": guid_lambert,
        "has_new_prescription": False,
        "prescription_has_anticoagulant": False,
        "prescription_removed_aspirin_only": False,
        "has_new_consultation_note": False,
    },
    # Issue 3: PERRIN — follow-up appointment needed
    "perrin": {
        "guid": guid_perrin,
        "has_new_agenda_entry": False,
        "agenda_date_future": False,
        "has_new_prescription": False,
        "has_new_consultation_note": False,
    },
    # Issue 4: NICOLAS — remove combined OCP, new prescription
    "nicolas": {
        "guid": guid_nicolas,
        "has_new_prescription": False,
        "new_prescription_lacks_ocp": False,
        "new_prescription_has_alternative": False,
        "has_new_consultation_note": False,
    },
}

# ---- DUBOIS Marie-Claire ----
new_presc = get_new_rubrics(guid_dubois, 20020100)
if new_presc:
    result["dubois"]["has_new_prescription"] = True
    content = (new_presc[0][2] or '').lower()
    antihyp = content_has(content, ['ramipril','amlodipine','bisoprolol','lisinopril','losartan','perindopril','valsartan','lercanidipine','nifedipine','atenolol','hydrochlorothiazide','indapamide'])
    antidiab = content_has(content, ['metformin','metformine','gliclazide','glipizide','sitagliptine','empagliflozine','dapagliflozine','insuline','insulin'])
    result["dubois"]["prescription_has_antihypertensive"] = len(antihyp) > 0
    result["dubois"]["prescription_has_antidiabetic"] = len(antidiab) > 0

new_cons = get_new_rubrics(guid_dubois, 20030000)
result["dubois"]["has_new_consultation_note"] = len(new_cons) > 0

# ---- LAMBERT Anne ----
new_presc = get_new_rubrics(guid_lambert, 20020100)
if new_presc:
    result["lambert"]["has_new_prescription"] = True
    content = (new_presc[0][2] or '').lower()
    anticoag = content_has(content, ['apixaban','rivaroxaban','dabigatran','acenocoumarol','warfarine','warfarin','fluindione','eliquis','xarelto','pradaxa'])
    result["lambert"]["prescription_has_anticoagulant"] = len(anticoag) > 0
    # Check if aspirin is still present (it shouldn't be the ONLY antiplatelet if AF is anticoagulated)
    still_aspirin_only = 'aspirine' in content and len(anticoag) == 0
    result["lambert"]["prescription_removed_aspirin_only"] = not still_aspirin_only

new_cons = get_new_rubrics(guid_lambert, 20030000)
result["lambert"]["has_new_consultation_note"] = len(new_cons) > 0

# ---- PERRIN Martine ----
if guid_perrin:
    cursor.execute("""
        SELECT PrimKey, Date_Time, Nom, Prenom, Note
        FROM agenda
        WHERE (GUID=%s OR (Nom='PERRIN' AND Prenom='Martine'))
          AND PrimKey > %s
        ORDER BY Date_Time ASC
    """, (guid_perrin, max_agenda_pk))
    agenda_rows = cursor.fetchall()
    if agenda_rows:
        result["perrin"]["has_new_agenda_entry"] = True
        # Check if the appointment date is in the future (after task start)
        for row in agenda_rows:
            dt_str = str(row[1]) if row[1] else ''
            if dt_str > '${TASK_START_DT}':
                result["perrin"]["agenda_date_future"] = True
                break

new_presc = get_new_rubrics(guid_perrin, 20020100)
result["perrin"]["has_new_prescription"] = len(new_presc) > 0
new_cons = get_new_rubrics(guid_perrin, 20030000)
result["perrin"]["has_new_consultation_note"] = len(new_cons) > 0

# ---- NICOLAS Sandrine ----
new_presc = get_new_rubrics(guid_nicolas, 20020100)
if new_presc:
    result["nicolas"]["has_new_prescription"] = True
    content = (new_presc[0][2] or '').lower()
    # Check the new prescription does NOT contain combined OCP
    has_ocp = any(kw in content for kw in ['ethinylestradiol','ethinyl','ludeal','minidril','varnoline','leeloo','optilova'])
    result["nicolas"]["new_prescription_lacks_ocp"] = not has_ocp
    # Check if an alternative contraception is prescribed
    alt_contraception = content_has(content, ['progestative','desogestrel','levonorgestrel','implant','sterilet','diu','cerazette','microval'])
    result["nicolas"]["new_prescription_has_alternative"] = len(alt_contraception) > 0

new_cons = get_new_rubrics(guid_nicolas, 20030000)
result["nicolas"]["has_new_consultation_note"] = len(new_cons) > 0

conn.close()
print(json.dumps(result, ensure_ascii=False, default=str))
PYEOF

echo "Result saved to /tmp/audit_result.json"
cat /tmp/audit_result.json
echo ""
echo "=== Export Complete ==="
