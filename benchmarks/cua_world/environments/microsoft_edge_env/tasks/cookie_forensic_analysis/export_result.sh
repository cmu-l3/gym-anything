#!/bin/bash
# Export script for Cookie Forensic Analysis task

echo "=== Exporting Cookie Forensic Analysis Result ==="

# Source shared utilities
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python to extract data safely
python3 << 'PYEOF'
import json, os, re, shutil, sqlite3, tempfile, sys

# 1. Get Task Start Time
try:
    with open("/tmp/task_start_ts_cookie_forensic_analysis.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 2. Query Browser Databases (History & Cookies)
# We copy them to temp files to avoid locking issues if Edge is running
edge_dir = "/home/ga/.config/microsoft-edge/Default"
history_db = os.path.join(edge_dir, "History")
cookies_db = os.path.join(edge_dir, "Cookies")

def query_db(db_path, query, args=()):
    if not os.path.exists(db_path):
        return []
    tmp_db = tempfile.mktemp(suffix=".sqlite")
    try:
        shutil.copy2(db_path, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        cursor.execute(query, args)
        rows = cursor.fetchall()
        conn.close()
        return rows
    except Exception as e:
        print(f"DB Query Error ({db_path}): {e}", file=sys.stderr)
        return []
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)

# Check History for visits
visits = {
    "cnn": False,
    "weather": False,
    "wikipedia": False
}
if os.path.exists(history_db):
    rows = query_db(history_db, "SELECT url, last_visit_time FROM urls")
    for row in rows:
        url = row[0].lower()
        # Chrome timestamps are microseconds since 1601... roughly check if recent
        # but primarily check existence of visit since we cleared history at start
        if "cnn.com" in url: visits["cnn"] = True
        if "weather.com" in url: visits["weather"] = True
        if "wikipedia.org" in url: visits["wikipedia"] = True

# Check Cookie DB for evidence of tracking
cookie_stats = {
    "total_count": 0,
    "recent_count": 0,
    "domains": []
}
if os.path.exists(cookies_db):
    # conversion: (creation_utc / 1000000) - 11644473600 = unix timestamp
    rows = query_db(cookies_db, "SELECT host_key, creation_utc FROM cookies")
    cookie_stats["total_count"] = len(rows)
    for row in rows:
        domain = row[0]
        creation_chrome = row[1]
        creation_unix = (creation_chrome / 1000000) - 11644473600
        
        cookie_stats["domains"].append(domain)
        if creation_unix > task_start:
            cookie_stats["recent_count"] += 1

# 3. Analyze Report File
report_path = "/home/ga/Desktop/cookie_forensic_report.txt"
report_data = {
    "exists": False,
    "modified_after_start": False,
    "size": 0,
    "content": ""
}

if os.path.exists(report_path):
    stats = os.stat(report_path)
    report_data["exists"] = True
    report_data["size"] = stats.st_size
    report_data["modified_after_start"] = stats.st_mtime > task_start
    try:
        with open(report_path, "r", errors="ignore") as f:
            report_data["content"] = f.read()
    except:
        pass

# 4. Construct Result JSON
result = {
    "task_start": task_start,
    "history_visits": visits,
    "cookie_stats": cookie_stats,
    "report": report_data
}

with open("/tmp/cookie_forensic_analysis_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Summary:")
print(f"Visits: {visits}")
print(f"Cookies: {cookie_stats['total_count']} total, {cookie_stats['recent_count']} recent")
print(f"Report: Exists={report_data['exists']}, Size={report_data['size']}")
PYEOF

echo "=== Export Complete ==="