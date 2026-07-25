#!/bin/bash
# export_result.sh — adu_permit_cost_research

echo "=== Exporting adu_permit_cost_research result ==="

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

TASK_START=$(cat /tmp/adu_permit_cost_research_task_start_timestamp 2>/dev/null || echo "0")
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

# Official permit / zoning sites
V_SANJOSE=$(_visits "sanjoseca.gov")
V_ABAG=$(_visits "abag.ca.gov")
V_HCD=$(_visits "hcd.ca.gov")
V_LEGINFO=$(_visits "leginfo.legislature.ca.gov")
V_PLANNING=$(_visits "planning.ca.gov")

# Contractor / cost research sites
V_CSLB=$(_visits "cslb.ca.gov")
V_HOUZZ=$(_visits "houzz.com")
V_THUMBTACK=$(_visits "thumbtack.com")
V_YELP=$(_visits "yelp.com")
V_ADUBLUEPRINT=$(_visits "adublueprint.com")
V_CASITA=$(_visits "casita.com")
V_BUILDINGANADU=$(_visits "buildinganadu.com")

python3 << PYEOF
import sqlite3, subprocess, json, re, os

task_start = int(open("/tmp/adu_permit_cost_research_task_start_timestamp").read().strip())
notes_db = os.path.expanduser("~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
coredata_start = task_start - 978307200

v_permit = sum(int(x) for x in [
    "$V_SANJOSE", "$V_ABAG", "$V_HCD", "$V_LEGINFO", "$V_PLANNING",
])
v_contractor = sum(int(x) for x in [
    "$V_CSLB", "$V_HOUZZ", "$V_THUMBTACK", "$V_YELP",
    "$V_ADUBLUEPRINT", "$V_CASITA", "$V_BUILDINGANADU",
])

KEYWORDS = ["permit", "adu", "setback", "contractor", "financing", "sqft", "accessible", "san jose"]

result = {
    "task_start": task_start,
    "visited_permit_site": v_permit > 0,
    "visited_contractor_site": v_contractor > 0,
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

with open("/tmp/adu_permit_cost_research_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Python export block complete")
PYEOF

screencapture /tmp/adu_permit_cost_research_end_screenshot.png 2>/dev/null || true

echo "=== Export complete for adu_permit_cost_research ==="
