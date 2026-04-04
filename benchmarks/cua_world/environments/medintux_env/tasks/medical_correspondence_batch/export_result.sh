#!/bin/bash
# Export script for medical_correspondence_batch task
# Checks whether new medical documents were created for each of the 3 target patients

echo "=== Exporting medical_correspondence_batch Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

take_screenshot /tmp/correspondence_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_DT=$(date -d "@${TASK_START}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-01-01 00:00:00")

python3 << PYEOF > /tmp/correspondence_result.json
import pymysql
import json

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

# Load baseline
try:
    with open('/tmp/correspondence_baseline.json') as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

task_start_dt = '${TASK_START_DT}'
max_baseline_pk = baseline.get('max_rubrique_pk', 0)

guid_roux = baseline.get('guid_roux')
guid_fournier = baseline.get('guid_fournier')
guid_gauthier = baseline.get('guid_gauthier')

# If GUIDs not in baseline, look them up
def get_guid(nom, prenom):
    cursor.execute(
        "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos=%s AND FchGnrl_Prenom=%s AND FchGnrl_Type='Dossier'",
        (nom, prenom)
    )
    row = cursor.fetchone()
    return row[0] if row else None

if not guid_roux:
    guid_roux = get_guid('ROUX', 'Celine') or get_guid('ROUX', 'C\xe9line')
if not guid_fournier:
    guid_fournier = get_guid('FOURNIER', 'Jacques')
if not guid_gauthier:
    guid_gauthier = get_guid('GAUTHIER', 'Helene') or get_guid('GAUTHIER', 'H\xe9l\xe8ne')

# Check document types: letters (20020500, 90010000) and certificates (20020300)
LETTER_TYPES = (20020500, 90010000)
CERT_TYPE = 20020300
ALL_DOC_TYPES = LETTER_TYPES + (CERT_TYPE,)

def get_new_docs(guid, type_rubs):
    """Get new documents created after task start for a patient."""
    if not guid:
        return []
    placeholders = ','.join(['%s'] * len(type_rubs))
    cursor.execute(f"""
        SELECT rh.RbDate_PrimKey, rh.RbDate_TypeRub, rh.RbDate_Date,
               CONVERT(rb.RbDate_DataRub USING utf8)
        FROM RubriquesHead rh
        LEFT JOIN RubriquesBlobs rb ON rh.RbDate_PrimKey = rb.RbDate_PrimKey
        WHERE rh.RbDate_IDDos=%s
          AND rh.RbDate_TypeRub IN ({placeholders})
          AND rh.RbDate_PrimKey > %s
        ORDER BY rh.RbDate_Date DESC
    """, (guid,) + tuple(type_rubs) + (max_baseline_pk,))
    return cursor.fetchall()

def check_keywords(content, keywords):
    content_lower = (content or '').lower()
    return [kw for kw in keywords if kw.lower() in content_lower]

result = {
    "task_start": ${TASK_START},
    "task_start_dt": task_start_dt,
    "guid_roux": guid_roux,
    "guid_fournier": guid_fournier,
    "guid_gauthier": guid_gauthier,
    "roux": {
        "has_new_letter": False,
        "letter_type_rub": None,
        "letter_keywords_found": [],
        "has_endocrinology_keyword": False,
    },
    "fournier": {
        "has_new_certificate": False,
        "cert_type_rub": None,
        "cert_keywords_found": [],
        "has_consolidation_keyword": False,
    },
    "gauthier": {
        "has_new_letter": False,
        "letter_type_rub": None,
        "letter_keywords_found": [],
        "has_cardiology_keyword": False,
    },
}

# Check ROUX Celine: needs letter (20020500 or 90010000) with endocrinology keyword
roux_docs = get_new_docs(guid_roux, LETTER_TYPES + (CERT_TYPE,))
for row in roux_docs:
    pk, type_rub, date, content = row
    if type_rub in LETTER_TYPES:
        result["roux"]["has_new_letter"] = True
        result["roux"]["letter_type_rub"] = type_rub
        found_kw = check_keywords(content, ["endocrinolog", "diabet", "hba1c", "9.2"])
        result["roux"]["letter_keywords_found"] = found_kw
        result["roux"]["has_endocrinology_keyword"] = "endocrinolog" in (content or "").lower()
        break

# Check FOURNIER Jacques: needs certificate (20020300) with consolidation keyword
fournier_docs = get_new_docs(guid_fournier, ALL_DOC_TYPES)
for row in fournier_docs:
    pk, type_rub, date, content = row
    if type_rub == CERT_TYPE:
        result["fournier"]["has_new_certificate"] = True
        result["fournier"]["cert_type_rub"] = type_rub
        found_kw = check_keywords(content, ["consolid", "travail", "entorse", "cheville", "reprise"])
        result["fournier"]["cert_keywords_found"] = found_kw
        result["fournier"]["has_consolidation_keyword"] = "consolid" in (content or "").lower()
        break
    elif type_rub in LETTER_TYPES and not result["fournier"]["has_new_certificate"]:
        # Accept a letter with consolidation content as partial
        content_lower = (content or "").lower()
        if "consolid" in content_lower:
            result["fournier"]["has_new_certificate"] = True
            result["fournier"]["cert_type_rub"] = type_rub
            result["fournier"]["has_consolidation_keyword"] = True

# Check GAUTHIER Helene: needs letter (20020500 or 90010000) with cardiology keyword
gauthier_docs = get_new_docs(guid_gauthier, LETTER_TYPES + (CERT_TYPE,))
for row in gauthier_docs:
    pk, type_rub, date, content = row
    if type_rub in LETTER_TYPES:
        result["gauthier"]["has_new_letter"] = True
        result["gauthier"]["letter_type_rub"] = type_rub
        found_kw = check_keywords(content, ["cardiolog", "palpitation", "holter", "arythmie"])
        result["gauthier"]["letter_keywords_found"] = found_kw
        result["gauthier"]["has_cardiology_keyword"] = "cardiolog" in (content or "").lower()
        break

conn.close()
print(json.dumps(result, ensure_ascii=False, default=str))
PYEOF

echo "Result saved to /tmp/correspondence_result.json"
cat /tmp/correspondence_result.json
echo ""
echo "=== Export Complete ==="
