#!/bin/bash
echo "=== Exporting media_library_management Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/media_library_management_final.png

# Focus LibreOffice window and save
WID=$(DISPLAY=:1 xdotool search --class soffice 2>/dev/null | head -1)
if [ -z "$WID" ]; then
    WID=$(DISPLAY=:1 xdotool search --name "chinook" 2>/dev/null | head -1)
fi

if [ -n "$WID" ]; then
    echo "Saving LibreOffice file..."
    DISPLAY=:1 xdotool windowfocus --sync "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+s
    sleep 4
    echo "Quitting LibreOffice (triggers HSQLDB SHUTDOWN)..."
    DISPLAY=:1 xdotool key ctrl+q
    sleep 2
    DISPLAY=:1 xdotool key Return
    sleep 1
else
    echo "WARNING: LibreOffice window not found"
fi

# Wait for clean exit
echo "Waiting for LibreOffice to exit..."
for i in $(seq 1 35); do
    if ! pgrep -f soffice > /dev/null 2>&1; then
        echo "LibreOffice exited after ${i}s"
        break
    fi
    sleep 1
done

if pgrep -f soffice > /dev/null 2>&1; then
    echo "Force-killing LibreOffice..."
    kill_libreoffice
fi

sleep 3

# Parse ODB file
python3 << 'PYEOF'
import zipfile
import re
import json
import html as html_mod

ODB_PATH = "/home/ga/chinook.odb"
ORIGINAL_TABLES_UPPER = {
    'MEDIATYPE', 'GENRE', 'ARTIST', 'EMPLOYEE', 'CUSTOMER',
    'ALBUM', 'TRACK', 'INVOICE', 'INVOICELINE', 'PLAYLIST', 'PLAYLISTTRACK'
}

result = {
    "query_names": [],
    "query_commands": {},
    "new_table_names": [],
    "all_table_names": [],
    "form_names": [],
    "report_names": [],
    "insert_counts": {},
    "track_review_ratings": [],
    "track_review_track_ids": [],
    "error": None
}

try:
    with zipfile.ZipFile(ODB_PATH, 'r') as zf:
        members = zf.namelist()

        if "content.xml" in members:
            content = zf.read("content.xml").decode("utf-8", errors="replace")

            for m in re.finditer(
                r'<db:query\b[^/]*?\bdb:name="([^"]+)"[^/]*?\bdb:command="([^"]*)"',
                content
            ):
                name, cmd = m.group(1), html_mod.unescape(m.group(2))
                if name not in result["query_names"]:
                    result["query_names"].append(name)
                result["query_commands"][name] = cmd

            for m in re.finditer(
                r'<db:query\b[^/]*?\bdb:command="([^"]*)"[^/]*?\bdb:name="([^"]+)"',
                content
            ):
                cmd, name = html_mod.unescape(m.group(1)), m.group(2)
                if name not in result["query_names"]:
                    result["query_names"].append(name)
                    result["query_commands"][name] = cmd

            forms_m = re.search(r'<db:forms\b[^>]*>(.*?)</db:forms>', content, re.DOTALL)
            if forms_m:
                result["form_names"] = re.findall(r'\bdb:name="([^"]+)"', forms_m.group(1))

            reports_m = re.search(r'<db:reports\b[^>]*>(.*?)</db:reports>', content, re.DOTALL)
            if reports_m:
                result["report_names"] = re.findall(r'\bdb:name="([^"]+)"', reports_m.group(1))

        if not result["form_names"]:
            form_dirs = set()
            for member in members:
                parts = member.split('/')
                if len(parts) >= 2 and parts[0] == 'forms' and parts[1]:
                    form_dirs.add(parts[1])
            result["form_names"] = list(form_dirs)

        if not result["report_names"]:
            report_dirs = set()
            for member in members:
                parts = member.split('/')
                if len(parts) >= 2 and parts[0] == 'reports' and parts[1]:
                    report_dirs.add(parts[1])
            result["report_names"] = list(report_dirs)

        if "database/script" in members:
            script = zf.read("database/script").decode("utf-8", errors="replace")

            tables = re.findall(
                r'CREATE (?:CACHED )?TABLE (?:PUBLIC\.)?"?([^"(\s]+)"?\s*\(',
                script, re.IGNORECASE
            )
            tables = [t.strip().strip('"') for t in tables]
            result["all_table_names"] = tables
            result["new_table_names"] = [
                t for t in tables if t.upper() not in ORIGINAL_TABLES_UPPER
            ]

            for tname in result["new_table_names"]:
                pattern2 = rf'INSERT INTO (?:PUBLIC\.)?"{re.escape(tname)}"'
                count = len(re.findall(pattern2, script, re.IGNORECASE))
                if count == 0:
                    pattern3 = rf'INSERT INTO (?:PUBLIC\.)?{re.escape(tname.upper())}[\s(]'
                    count = len(re.findall(pattern3, script, re.IGNORECASE))
                result["insert_counts"][tname] = count

            # Extract TrackReview data for validation
            # Format: INSERT INTO "TrackReview" VALUES(1,42,5,'Great track','2024-01-15')
            tr_inserts = re.findall(
                r'INSERT INTO (?:PUBLIC\.)?(?:"TrackReview"|"TRACKREVIEW"|TRACKREVIEW)\s+VALUES\s*\(([^)]+)\)',
                script, re.IGNORECASE
            )
            ratings = []
            track_ids = []
            for ins in tr_inserts:
                parts = [p.strip().strip("'\"") for p in ins.split(',')]
                if len(parts) >= 3:
                    try:
                        track_ids.append(int(parts[1]))
                        ratings.append(int(parts[2]))
                    except (ValueError, IndexError):
                        pass
            result["track_review_ratings"] = ratings
            result["track_review_track_ids"] = track_ids

except Exception as e:
    import traceback
    result["error"] = str(e)
    result["traceback"] = traceback.format_exc()

with open("/tmp/media_library_management_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Queries: {result['query_names']}")
print(f"New tables: {result['new_table_names']}")
print(f"TrackReview rows: {len(result['track_review_ratings'])}, ratings: {result['track_review_ratings']}")
print(f"Reports: {result['report_names']}")
if result.get("error"):
    print(f"ERROR: {result['error']}")
PYEOF

echo "=== Export Complete ==="
