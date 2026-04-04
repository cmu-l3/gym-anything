#!/bin/bash
echo "=== Exporting genre_revenue_queries Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/genre_revenue_queries_final.png
echo "Final screenshot saved."

# Focus LibreOffice window and save the file
WID=$(DISPLAY=:1 xdotool search --class soffice 2>/dev/null | head -1)
if [ -z "$WID" ]; then
    WID=$(DISPLAY=:1 xdotool search --name "chinook" 2>/dev/null | head -1)
fi

if [ -n "$WID" ]; then
    echo "Found LibreOffice window: $WID, saving..."
    DISPLAY=:1 xdotool windowfocus --sync "$WID" 2>/dev/null || true
    sleep 0.5
    # Save file (flushes content.xml with queries/forms/reports)
    DISPLAY=:1 xdotool key ctrl+s
    sleep 4
    echo "File saved. Quitting LibreOffice..."
    # Quit LibreOffice (triggers HSQLDB SHUTDOWN which flushes database/script)
    DISPLAY=:1 xdotool key ctrl+q
    sleep 2
    # Handle any "keep changes?" dialog
    DISPLAY=:1 xdotool key Return
    sleep 1
else
    echo "WARNING: LibreOffice window not found, proceeding anyway"
fi

# Wait for LibreOffice to fully exit (HSQLDB writes database/script on SHUTDOWN)
echo "Waiting for LibreOffice to exit (HSQLDB SHUTDOWN)..."
for i in $(seq 1 35); do
    if ! pgrep -f soffice > /dev/null 2>&1; then
        echo "LibreOffice exited cleanly after ${i}s"
        break
    fi
    sleep 1
done

# Force-kill if still running
if pgrep -f soffice > /dev/null 2>&1; then
    echo "WARNING: LibreOffice still running, force-killing..."
    kill_libreoffice
fi

sleep 3

# Parse ODB file and extract verification data
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
    "error": None
}

try:
    with zipfile.ZipFile(ODB_PATH, 'r') as zf:
        members = zf.namelist()

        # Parse content.xml for queries, forms, reports
        if "content.xml" in members:
            content = zf.read("content.xml").decode("utf-8", errors="replace")

            # Extract query names and commands (handle both attribute orders)
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

            # Extract form names from content.xml <db:forms> section
            forms_m = re.search(r'<db:forms\b[^>]*>(.*?)</db:forms>', content, re.DOTALL)
            if forms_m:
                result["form_names"] = re.findall(r'\bdb:name="([^"]+)"', forms_m.group(1))

            # Extract report names from content.xml <db:reports> section
            reports_m = re.search(r'<db:reports\b[^>]*>(.*?)</db:reports>', content, re.DOTALL)
            if reports_m:
                result["report_names"] = re.findall(r'\bdb:name="([^"]+)"', reports_m.group(1))

        # Fallback: check ZIP structure for forms/reports
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

        # Parse database/script for tables and insert counts
        if "database/script" in members:
            script = zf.read("database/script").decode("utf-8", errors="replace")

            # Find all CREATE TABLE statements
            tables = re.findall(
                r'CREATE (?:CACHED )?TABLE (?:PUBLIC\.)?"?([^"(\s]+)"?\s*\(',
                script, re.IGNORECASE
            )
            tables = [t.strip().strip('"') for t in tables]
            result["all_table_names"] = tables
            result["new_table_names"] = [
                t for t in tables if t.upper() not in ORIGINAL_TABLES_UPPER
            ]

            # Count INSERT rows per new table
            for tname in result["new_table_names"]:
                pattern = rf'INSERT INTO (?:PUBLIC\.)?(?:"{re.escape(tname)}"|{re.escape(tname.upper())})\s*[\(,\s]'
                count = len(re.findall(pattern, script, re.IGNORECASE))
                result["insert_counts"][tname] = count

except Exception as e:
    import traceback
    result["error"] = str(e)
    result["traceback"] = traceback.format_exc()

with open("/tmp/genre_revenue_queries_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Queries found: {result['query_names']}")
print(f"New tables: {result['new_table_names']}")
print(f"Insert counts: {result['insert_counts']}")
print(f"Forms: {result['form_names']}")
print(f"Reports: {result['report_names']}")
if result.get("error"):
    print(f"ERROR: {result['error']}")
PYEOF

echo "=== Export Complete ==="
