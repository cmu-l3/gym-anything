#!/bin/bash
# Export script for polypharmacy_review_and_update task
# Queries which new prescription and consultation rubrics were created for the 4 target patients

echo "=== Exporting polypharmacy_review_and_update Result ==="

source /workspace/scripts/task_utils.sh

if ! type medintux_query &>/dev/null; then
    medintux_query() { mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

take_screenshot /tmp/polypharmacy_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_DT=$(date -d "@${TASK_START}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-01-01 00:00:00")

GUID_MARTIN="0E78F6AF-9396-4000-A4C2-29FFE96C6205"
GUID_BERNARD="EFE754AE-2CFD-4C06-A3F9-6D1AE2B18ABC"
GUID_MOREAU="E87A5020-F471-4046-96C3-59852DF10DE2"
GUID_LEROY="4E8D739F-2A13-4CA7-907D-2CC8B1E5AC71"

# Query new prescriptions (TypeRub=20020100) created after task start for each patient
new_ordo_query() {
    local guid="$1"
    medintux_query "SELECT COUNT(*) FROM RubriquesHead WHERE RbDate_IDDos='$guid' AND RbDate_TypeRub=20020100 AND RbDate_Date > '${TASK_START_DT}';"
}

# Query new consultation rubrics (TypeRub=20030000) created after task start
new_cons_query() {
    local guid="$1"
    medintux_query "SELECT COUNT(*) FROM RubriquesHead WHERE RbDate_IDDos='$guid' AND RbDate_TypeRub=20030000 AND RbDate_Date > '${TASK_START_DT}';"
}

MARTIN_NEW_ORDO=$(new_ordo_query "$GUID_MARTIN")
MARTIN_NEW_CONS=$(new_cons_query "$GUID_MARTIN")
BERNARD_NEW_ORDO=$(new_ordo_query "$GUID_BERNARD")
BERNARD_NEW_CONS=$(new_cons_query "$GUID_BERNARD")
MOREAU_NEW_ORDO=$(new_ordo_query "$GUID_MOREAU")
MOREAU_NEW_CONS=$(new_cons_query "$GUID_MOREAU")
LEROY_NEW_ORDO=$(new_ordo_query "$GUID_LEROY")
LEROY_NEW_CONS=$(new_cons_query "$GUID_LEROY")

# Default to 0 if empty
MARTIN_NEW_ORDO=${MARTIN_NEW_ORDO:-0}
MARTIN_NEW_CONS=${MARTIN_NEW_CONS:-0}
BERNARD_NEW_ORDO=${BERNARD_NEW_ORDO:-0}
BERNARD_NEW_CONS=${BERNARD_NEW_CONS:-0}
MOREAU_NEW_ORDO=${MOREAU_NEW_ORDO:-0}
MOREAU_NEW_CONS=${MOREAU_NEW_CONS:-0}
LEROY_NEW_ORDO=${LEROY_NEW_ORDO:-0}
LEROY_NEW_CONS=${LEROY_NEW_CONS:-0}

echo "New prescriptions: MARTIN=$MARTIN_NEW_ORDO BERNARD=$BERNARD_NEW_ORDO MOREAU=$MOREAU_NEW_ORDO LEROY=$LEROY_NEW_ORDO"
echo "New consultations: MARTIN=$MARTIN_NEW_CONS BERNARD=$BERNARD_NEW_CONS MOREAU=$MOREAU_NEW_CONS LEROY=$LEROY_NEW_CONS"

# Also check blob content of new prescriptions for correctness signal
# Using Python to read and parse the blobs
python3 << PYEOF > /tmp/polypharmacy_content.json
import pymysql, json

conn = pymysql.connect(host='localhost', user='root', db='DrTuxTest', charset='latin1')
cursor = conn.cursor()

guids = {
    'martin': '0E78F6AF-9396-4000-A4C2-29FFE96C6205',
    'bernard': 'EFE754AE-2CFD-4C06-A3F9-6D1AE2B18ABC',
    'moreau': 'E87A5020-F471-4046-96C3-59852DF10DE2',
    'leroy': '4E8D739F-2A13-4CA7-907D-2CC8B1E5AC71',
}
task_start_dt = '${TASK_START_DT}'
result = {}

for name, guid in guids.items():
    cursor.execute("""
        SELECT rh.RbDate_PrimKey, CONVERT(rb.RbDate_DataRub USING utf8)
        FROM RubriquesHead rh
        LEFT JOIN RubriquesBlobs rb ON rh.RbDate_PrimKey = rb.RbDate_PrimKey
        WHERE rh.RbDate_IDDos=%s AND rh.RbDate_TypeRub=20020100
        AND rh.RbDate_Date > %s
        ORDER BY rh.RbDate_Date DESC LIMIT 1
    """, (guid, task_start_dt))
    row = cursor.fetchone()
    if row:
        content = (row[1] or '').lower()
        result[f'{name}_new_prescription_text'] = content[:500]
    else:
        result[f'{name}_new_prescription_text'] = ''

conn.close()
print(json.dumps(result))
PYEOF

cat > /tmp/polypharmacy_result.json << EOF
{
    "task_start": ${TASK_START},
    "task_start_dt": "${TASK_START_DT}",
    "martin_new_ordo": ${MARTIN_NEW_ORDO},
    "martin_new_cons": ${MARTIN_NEW_CONS},
    "bernard_new_ordo": ${BERNARD_NEW_ORDO},
    "bernard_new_cons": ${BERNARD_NEW_CONS},
    "moreau_new_ordo": ${MOREAU_NEW_ORDO},
    "moreau_new_cons": ${MOREAU_NEW_CONS},
    "leroy_new_ordo": ${LEROY_NEW_ORDO},
    "leroy_new_cons": ${LEROY_NEW_CONS}
}
EOF

echo "Result saved to /tmp/polypharmacy_result.json"
echo "=== Export Complete ==="
