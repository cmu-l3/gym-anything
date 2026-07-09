#!/bin/bash
# export_result.sh — pediatric_specialist_search

echo "=== Exporting pediatric_specialist_search result ==="

osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
sleep 3

HISTORY_DB="/Users/lume/Library/Safari/History.db"
if [ -f "$HISTORY_DB" ]; then
    sqlite3 "$HISTORY_DB" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
fi

NOTES_DB="$HOME/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
if [ -f "$NOTES_DB" ]; then
    sqlite3 "$NOTES_DB" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
fi

TASK_START=$(cat /tmp/pediatric_specialist_search_task_start_timestamp 2>/dev/null || echo "0")
MAC_TASK_START=$(python3 -c "print(int('$TASK_START') - 978307200)" 2>/dev/null || echo "0")

_visits() {
    local pattern="$1"
    if [ ! -f "$HISTORY_DB" ]; then echo "0"; return; fi
    sqlite3 "$HISTORY_DB" \
        "SELECT COUNT(*) FROM history_visits hv
         JOIN history_items hi ON hv.history_item = hi.id
         WHERE hi.url LIKE '%${pattern}%'
         AND hv.visit_time > ${MAC_TASK_START};" 2>/dev/null || echo "0"
}

# Medical directories and children's hospitals
V_HEALTHGRADES=$(_visits "healthgrades.com")
V_ZOCDOC=$(_visits "zocdoc.com")
V_VITALS=$(_visits "vitals.com")
V_LURIE=$(_visits "luriechildrens.org")
V_NM=$(_visits "nm.org")
V_UCHICAGO=$(_visits "uchicagomedicine.org")
V_NORTHSHORE=$(_visits "northshore.org")
V_ADVOCATE=$(_visits "advocatehealth.com")
V_RUSH=$(_visits "rush.edu")
V_BCBS=$(_visits "bcbsil.com")

# Disease / treatment reference sites
V_ARTHRITIS=$(_visits "arthritis.org")
V_ACR=$(_visits "rheumatology.org")
V_CREAKY=$(_visits "creakyjoints.org")
V_CLINTRIALS=$(_visits "clinicaltrials.gov")
V_MAYO=$(_visits "mayoclinic.org")
V_PUBMED=$(_visits "ncbi.nlm.nih.gov")

python3 << PYEOF
import sqlite3, subprocess, json, re, os

task_start = int(open("/tmp/pediatric_specialist_search_task_start_timestamp").read().strip())
notes_db = os.path.expanduser("~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
coredata_start = task_start - 978307200

v_medical = sum(int(x) for x in [
    "$V_HEALTHGRADES", "$V_ZOCDOC", "$V_VITALS", "$V_LURIE",
    "$V_NM", "$V_UCHICAGO", "$V_NORTHSHORE", "$V_ADVOCATE",
    "$V_RUSH", "$V_BCBS",
])
v_disease = sum(int(x) for x in [
    "$V_ARTHRITIS", "$V_ACR", "$V_CREAKY",
    "$V_CLINTRIALS", "$V_MAYO", "$V_PUBMED",
])

KEYWORDS = ["rheumatologist", "specialist", "hospital", "bcbs", "insurance", "treatment", "appointment", "arthritis", "jia"]

result = {
    "task_start": task_start,
    "visited_medical_directory": v_medical > 0,
    "visited_disease_info_site": v_disease > 0,
    "note_found": False,
    "note_is_fresh": False,
    "note_title": "",
    "note_length": 0,
    "note_keyword_count": 0,
    "note_keywords_found": [],
}

fresh_titles = []
if os.path.exists(notes_db):
    try:
        conn = sqlite3.connect(f"file:{notes_db}?mode=ro&immutable=1", uri=True)
        rows = conn.execute("""
            SELECT ZTITLE1, ZMODIFICATIONDATE1
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZTITLE1 IS NOT NULL
            AND ZMODIFICATIONDATE1 > ?
            ORDER BY ZMODIFICATIONDATE1 DESC
            LIMIT 5
        """, (coredata_start,)).fetchall()
        conn.close()
        fresh_titles = [row[0] for row in rows if row[0]]
    except Exception as e:
        result["notes_db_error"] = str(e)

if fresh_titles:
    result["note_found"] = True
    result["note_is_fresh"] = True
    result["note_title"] = fresh_titles[0]

best_length = 0
best_keywords = []
for title in (fresh_titles[:3] if fresh_titles else []):
    safe = title.replace("\\", "\\\\").replace('"', '\\"')
    proc = subprocess.run(
        ["osascript", "-e",
         f'tell application "Notes"\ntry\nreturn body of note "{safe}"\non error\nreturn ""\nend try\nend tell'],
        capture_output=True, text=True, timeout=20
    )
    body_html = proc.stdout.strip() if proc.returncode == 0 else ""
    if not body_html:
        continue
    body_text = re.sub(r'<[^>]+>', ' ', body_html)
    if len(body_text) > best_length:
        best_length = len(body_text)
        body_lower = body_text.lower()
        best_keywords = [k for k in KEYWORDS if k in body_lower]

if best_length == 0:
    proc = subprocess.run(
        ["osascript", "-e", 'tell application "Notes" to return body of note 1'],
        capture_output=True, text=True, timeout=20
    )
    if proc.returncode == 0 and proc.stdout.strip():
        body_text = re.sub(r'<[^>]+>', ' ', proc.stdout.strip())
        best_length = len(body_text)
        body_lower = body_text.lower()
        best_keywords = [k for k in KEYWORDS if k in body_lower]

result["note_length"] = best_length
result["note_keywords_found"] = best_keywords
result["note_keyword_count"] = len(best_keywords)

with open("/tmp/pediatric_specialist_search_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Python export block complete")
PYEOF

screencapture /tmp/pediatric_specialist_search_end_screenshot.png 2>/dev/null || true

echo "=== Export complete for pediatric_specialist_search ==="
