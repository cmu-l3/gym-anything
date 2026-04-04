#!/bin/bash
echo "=== Setting up genre_revenue_queries task ==="

source /workspace/scripts/task_utils.sh

# Kill any running LibreOffice instances
kill_libreoffice

# Restore a fresh copy of chinook.odb
restore_chinook_odb

# Record baseline state from the freshly restored ODB (before LO opens and locks it)
python3 << 'PYEOF'
import zipfile
import re
import json

ODB_PATH = "/home/ga/chinook.odb"
ORIGINAL_TABLES_UPPER = {
    'MEDIATYPE', 'GENRE', 'ARTIST', 'EMPLOYEE', 'CUSTOMER',
    'ALBUM', 'TRACK', 'INVOICE', 'INVOICELINE', 'PLAYLIST', 'PLAYLISTTRACK'
}

baseline = {
    "query_count": 0,
    "query_names": [],
    "form_count": 0,
    "report_count": 0,
    "new_table_count": 0,
    "new_table_names": [],
    "all_table_names": [],
}

try:
    with zipfile.ZipFile(ODB_PATH, 'r') as zf:
        members = zf.namelist()
        if "content.xml" in members:
            content = zf.read("content.xml").decode("utf-8", errors="replace")
            queries = re.findall(r'<db:query\b[^/]*?\bdb:name="([^"]+)"', content)
            baseline["query_names"] = queries
            baseline["query_count"] = len(queries)
            forms_m = re.search(r'<db:forms\b[^>]*>(.*?)</db:forms>', content, re.DOTALL)
            baseline["form_count"] = len(re.findall(r'\bdb:name="', forms_m.group(1))) if forms_m else 0
            reports_m = re.search(r'<db:reports\b[^>]*>(.*?)</db:reports>', content, re.DOTALL)
            baseline["report_count"] = len(re.findall(r'\bdb:name="', reports_m.group(1))) if reports_m else 0
        if "database/script" in members:
            script = zf.read("database/script").decode("utf-8", errors="replace")
            tables = re.findall(
                r'CREATE (?:CACHED )?TABLE (?:PUBLIC\.)?"?([^"(\s]+)"?\s*\(',
                script, re.IGNORECASE
            )
            tables = [t.strip().strip('"') for t in tables]
            baseline["all_table_names"] = tables
            new_tables = [t for t in tables if t.upper() not in ORIGINAL_TABLES_UPPER]
            baseline["new_table_count"] = len(new_tables)
            baseline["new_table_names"] = new_tables
except Exception as e:
    baseline["error"] = str(e)

with open("/tmp/genre_revenue_queries_initial.json", "w") as f:
    json.dump(baseline, f, indent=2)

print(f"Baseline: {baseline['query_count']} queries, {baseline['new_table_count']} new tables, "
      f"{baseline['form_count']} forms, {baseline['report_count']} reports")
PYEOF

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Launch LibreOffice Base with chinook.odb
launch_libreoffice_base /home/ga/chinook.odb
wait_for_libreoffice_base 45
sleep 3
dismiss_dialogs
sleep 1
maximize_libreoffice
sleep 1

# Take initial screenshot
take_screenshot /tmp/genre_revenue_queries_start.png
echo "Initial screenshot saved."

echo "=== genre_revenue_queries task ready ==="
echo "LibreOffice Base is open with chinook.odb (Chinook music store database)."
echo "Agent must: create GenreRevenue and CountryRevenue queries, RevenueTarget table with 4+ rows, and a Revenue Analysis report."
