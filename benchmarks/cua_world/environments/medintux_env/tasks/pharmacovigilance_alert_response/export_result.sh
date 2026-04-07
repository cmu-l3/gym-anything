#!/bin/bash
# export_result.sh — Pharmacovigilance Alert Response
# Queries the database for new prescriptions, consultation notes, and agenda
# entries created by the agent. Checks for the summary CSV report.

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type medintux_query &>/dev/null; then
    medintux_query() { mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

take_screenshot /tmp/pharma_alert_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_DT=$(date -d "@${TASK_START}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-01-01 00:00:00")

python3 << PYEOF > /tmp/pharma_alert_result.json
import pymysql
import json
import os

conn = pymysql.connect(host='localhost', user='root', database='DrTuxTest', charset='latin1')
cursor = conn.cursor()

# Load baseline
try:
    with open('/tmp/pharma_alert_baseline.json', 'r') as f:
        baseline = json.load(f)
    max_rub_pk = baseline['max_rubrique_pk']
    max_agenda_pk = baseline['max_agenda_pk']
    patient_guids = baseline['patient_guids']
except Exception as e:
    print(json.dumps({"error": f"Failed to load baseline: {e}"}))
    raise SystemExit(1)

task_start_dt = "${TASK_START_DT}"

def get_new_rubrics(guid, type_rub):
    """Get new rubric entries created after baseline for a given patient and type."""
    cursor.execute(
        """SELECT rh.RbDate_PrimKey, rh.RbDate_Date,
                  CONVERT(rb.RbDate_DataRub USING utf8) as content
           FROM RubriquesHead rh
           LEFT JOIN RubriquesBlobs rb ON rh.RbDate_RefBlobs_PrimKey = rb.RbDate_PrimKey
           WHERE rh.RbDate_IDDos = %s
             AND rh.RbDate_TypeRub = %s
             AND rh.RbDate_PrimKey > %s
           ORDER BY rh.RbDate_PrimKey DESC""",
        (guid, type_rub, max_rub_pk))
    rows = cursor.fetchall()
    return [{"pk": r[0], "date": str(r[1]), "content": r[2] or ""} for r in rows]

def get_new_agenda(guid, nom, prenom):
    """Get new agenda entries created after baseline for a given patient."""
    cursor.execute(
        """SELECT PrimKey, Date_Time, Note
           FROM agenda
           WHERE PrimKey > %s
             AND (GUID = %s OR (Nom = %s AND Prenom = %s))
           ORDER BY PrimKey DESC""",
        (max_agenda_pk, guid, nom, prenom))
    rows = cursor.fetchall()
    return [{"pk": r[0], "datetime": str(r[1]), "note": r[2] or ""} for r in rows]

def content_has(content, keywords):
    """Check if content contains any of the keywords (case-insensitive)."""
    if not content:
        return False
    lower = content.lower()
    return any(kw.lower() in lower for kw in keywords)

# --- Collect results per patient ---

result = {
    "task_start": task_start_dt,
    "baseline": baseline,
    "patients": {}
}

patient_meta = {
    "DUBOIS": {"nom": "DUBOIS", "prenom": "Marie-Claire"},
    "MARTIN": {"nom": "MARTIN", "prenom": "Sophie"},
    "PETIT":  {"nom": "PETIT",  "prenom": "Nathalie"},
    "HENRY":  {"nom": "HENRY",  "prenom": "Emmanuel"},
}

for name, meta in patient_meta.items():
    guid = patient_guids.get(name, "")
    nom = meta["nom"]
    prenom = meta["prenom"]

    new_prescriptions = get_new_rubrics(guid, 20020100)
    new_consultations = get_new_rubrics(guid, 20030000)
    new_agenda = get_new_agenda(guid, nom, prenom)

    # Check latest prescription content for expected keywords
    latest_rx_content = new_prescriptions[0]["content"] if new_prescriptions else ""

    result["patients"][name] = {
        "guid": guid,
        "nom": nom,
        "prenom": prenom,
        "has_new_prescription": len(new_prescriptions) > 0,
        "new_prescription_count": len(new_prescriptions),
        "latest_prescription_content": latest_rx_content[:2000],
        "rx_has_sitagliptine": content_has(latest_rx_content, ["sitagliptine", "sitagliptin"]),
        "rx_has_metformine_500": content_has(latest_rx_content, ["metformine 500", "500mg"]) and content_has(latest_rx_content, ["metformine"]),
        "rx_has_glucophage": content_has(latest_rx_content, ["glucophage"]),
        "rx_has_repaglinide": content_has(latest_rx_content, ["repaglinide", "reaglinide"]),
        "rx_has_metformine_850": content_has(latest_rx_content, ["metformine 850"]),
        "has_new_consultation": len(new_consultations) > 0,
        "new_consultation_count": len(new_consultations),
        "latest_consultation_content": (new_consultations[0]["content"] if new_consultations else "")[:2000],
        "note_references_alert": content_has(
            new_consultations[0]["content"] if new_consultations else "",
            ["CRPV", "0847", "pharmacovigilance", "alerte"]),
        "has_new_agenda": len(new_agenda) > 0,
        "new_agenda_count": len(new_agenda),
        "agenda_entries": new_agenda[:5],
    }

# --- Check for summary CSV report ---

csv_path = os.path.expanduser("~/Documents/rapport_pharmacovigilance_CRPV-2026-0847.csv")
# Also check /home/ga path directly
if not os.path.exists(csv_path):
    csv_path = "/home/ga/Documents/rapport_pharmacovigilance_CRPV-2026-0847.csv"

csv_exists = os.path.exists(csv_path)
csv_content = ""
if csv_exists:
    try:
        with open(csv_path, 'r', errors='replace') as f:
            csv_content = f.read()[:5000]
    except Exception:
        csv_content = ""

result["csv_report"] = {
    "exists": csv_exists,
    "path": csv_path,
    "content": csv_content,
    "has_dubois": "DUBOIS" in csv_content.upper() if csv_content else False,
    "has_martin": "MARTIN" in csv_content.upper() if csv_content else False,
    "has_petit": "PETIT" in csv_content.upper() if csv_content else False,
    "has_henry": "HENRY" in csv_content.upper() if csv_content else False,
}

cursor.close()
conn.close()

print(json.dumps(result, ensure_ascii=False, default=str))
PYEOF

echo "Export complete: pharmacovigilance_alert_response"
