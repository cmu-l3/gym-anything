#!/bin/bash
# export_result.sh - Post-task hook for devtools_cascading_debug
#
# Collects evidence: source file state, incident report, browser history, bookmarks.

echo "=== Exporting devtools_cascading_debug results ==="

# ── 1. Capture final screenshot ──
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ── 2. Kill Firefox to flush SQLite WAL ──
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# ── 3. Read task metadata ──
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# Fallback profile search
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    for candidate in \
        "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
        "/home/ga/.mozilla/firefox/default.profile"; do
        if [ -f "$candidate/places.sqlite" ]; then
            PROFILE_DIR="$candidate"
            break
        fi
    done
fi

# ── 4. Query browser history and bookmarks via SQLite ──
LOCALHOST_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    sqlite3 "$PROFILE_DIR/places.sqlite" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_cascading_debug_$$.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null

    if [ -f "$TEMP_DB" ]; then
        LOCALHOST_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%localhost:8080%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        BOOKMARK_FOLDER_EXISTS=$(sqlite3 "$TEMP_DB" \
            "SELECT CASE WHEN COUNT(*) > 0 THEN 'true' ELSE 'false' END
             FROM moz_bookmarks WHERE title = 'Development' AND type = 2;" 2>/dev/null || echo "false")

        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks b1
             JOIN moz_bookmarks b2 ON b1.parent = b2.id
             WHERE b2.title = 'Development' AND b1.type = 1;" 2>/dev/null || echo "0")

        rm -f "$TEMP_DB"
    fi
fi

# ── 5. Write shell-collected data to temp file for Python ──
cat > /tmp/shell_data.json << SHELLJSON
{
    "localhost_visits": $LOCALHOST_VISITS,
    "bookmark_folder_exists": $( [ "$BOOKMARK_FOLDER_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "bookmark_count": $BOOKMARK_COUNT
}
SHELLJSON

# ── 6. Run Python analysis (file checks, bug detection, report parsing) ──
python3 << 'PYEOF'
import json
import os
import subprocess

TASK_START = 0
if os.path.exists("/tmp/task_start_timestamp"):
    TASK_START = int(open("/tmp/task_start_timestamp").read().strip())

# Load shell-collected browser data
shell_data = {"localhost_visits": 0, "bookmark_folder_exists": False, "bookmark_count": 0}
try:
    with open("/tmp/shell_data.json", "r") as f:
        shell_data = json.load(f)
except Exception:
    pass

result = {
    "task_start": TASK_START,
    "localhost_visits": shell_data.get("localhost_visits", 0),
    "bookmark_folder_exists": shell_data.get("bookmark_folder_exists", False),
    "bookmark_count": shell_data.get("bookmark_count", 0),
    "source_files": {},
    "incident_report": {},
    "http_server_running": False,
    "bugs_fixed": {}
}

# -- Check HTTP server --
try:
    r = subprocess.run(
        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:8080"],
        capture_output=True, text=True, timeout=5
    )
    result["http_server_running"] = r.stdout.strip() == "200"
except Exception:
    result["http_server_running"] = False

# -- Read current source files --
for fname in ["index.html", "app.js", "style.css"]:
    fpath = os.path.join("/home/ga/webapp", fname)
    if os.path.exists(fpath):
        try:
            with open(fpath, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            result["source_files"][fname] = {
                "exists": True,
                "size": os.path.getsize(fpath),
                "mtime": int(os.path.getmtime(fpath)),
                "content": content
            }
        except Exception as e:
            result["source_files"][fname] = {"exists": True, "error": str(e)}
    else:
        result["source_files"][fname] = {"exists": False}

# -- Check which bugs were fixed --
index_content = result["source_files"].get("index.html", {}).get("content", "")
appjs_content = result["source_files"].get("app.js", {}).get("content", "")

# Bug 1: script src app.jss -> app.js (check for exact attribute, not substring)
bug1_fixed = ('src="app.js"' in index_content or "src='app.js'" in index_content) and \
             ("app.jss" not in index_content)
result["bugs_fixed"]["bug1_script_src"] = bug1_fixed

# Bug 2: fetch URL employee.json -> employees.json
# Check that employees.json is present and standalone employee.json is not
bug2_fixed = "employees.json" in appjs_content
if bug2_fixed:
    # Make sure there isn't still a bare "employee.json" (not part of "employees.json")
    temp = appjs_content.replace("employees.json", "")
    bug2_fixed = "employee.json" not in temp
result["bugs_fixed"]["bug2_fetch_url"] = bug2_fixed

# Bug 3: data.employees -> data.staff
bug3_fixed = "data.staff" in appjs_content and "data.employees" not in appjs_content
result["bugs_fixed"]["bug3_data_property"] = bug3_fixed

# Bug 4: emp-row -> employee-row (in the JS class assignment)
bug4_fixed = "employee-row" in appjs_content
if bug4_fixed:
    temp = appjs_content.replace("employee-row", "")
    bug4_fixed = "emp-row" not in temp
result["bugs_fixed"]["bug4_css_class"] = bug4_fixed

# Bug 5: filterTable -> searchTable in HTML, OR searchTable renamed to filterTable in JS
bug5_fixed = (
    ("searchTable" in index_content and "filterTable" not in index_content) or
    ("filterTable" in appjs_content and "function filterTable" in appjs_content)
)
result["bugs_fixed"]["bug5_handler_name"] = bug5_fixed

result["bugs_fixed_count"] = sum(1 for v in result["bugs_fixed"].values() if v is True)

# -- Were files modified from originals? --
for fname, tmpname in [("index.html", "/tmp/original_index.html"), ("app.js", "/tmp/original_app.js")]:
    if os.path.exists(tmpname):
        with open(tmpname, "r", encoding="utf-8", errors="replace") as f:
            original = f.read()
        current = result["source_files"].get(fname, {}).get("content", "")
        result.setdefault("source_files_modified", {})[fname] = (current != original)

# -- Read incident report --
report_path = "/home/ga/Documents/incident_report.json"
if os.path.exists(report_path):
    rstat = os.stat(report_path)
    result["incident_report"]["exists"] = True
    result["incident_report"]["size"] = rstat.st_size
    result["incident_report"]["mtime"] = int(rstat.st_mtime)
    result["incident_report"]["fresh"] = int(rstat.st_mtime) > TASK_START
    try:
        with open(report_path, "r", encoding="utf-8") as f:
            report_data = json.load(f)
        result["incident_report"]["valid_json"] = True
        result["incident_report"]["content"] = report_data

        # Handle both array-at-root and {issues: [...]} formats
        issues_list = []
        if isinstance(report_data, list):
            issues_list = report_data
        elif isinstance(report_data, dict):
            for key in ["issues", "bugs", "findings"]:
                if key in report_data and isinstance(report_data[key], list):
                    issues_list = report_data[key]
                    break

        result["incident_report"]["issue_count"] = len(issues_list)

        required_fields = {"symptom", "root_cause", "file_modified", "fix_applied", "devtools_panel"}
        complete_issues = 0
        for issue in issues_list:
            if isinstance(issue, dict) and required_fields.issubset(set(issue.keys())):
                complete_issues += 1
        result["incident_report"]["complete_issue_count"] = complete_issues

    except json.JSONDecodeError as e:
        result["incident_report"]["valid_json"] = False
        result["incident_report"]["json_error"] = str(e)
else:
    result["incident_report"]["exists"] = False

# -- Write final result (exclude raw file content to keep output manageable) --
output = dict(result)
for fname in list(output.get("source_files", {}).keys()):
    if "content" in output["source_files"].get(fname, {}):
        # Keep content for verifier but truncate for display
        pass

with open("/tmp/devtools_cascading_debug_result.json", "w") as f:
    json.dump(output, f, indent=2, default=str)

print("Export analysis complete.")
PYEOF

chmod 644 /tmp/devtools_cascading_debug_result.json

echo "=== Export complete ==="
# Print summary (without full file contents)
python3 -c "
import json
with open('/tmp/devtools_cascading_debug_result.json') as f:
    d = json.load(f)
# Remove bulky content for display
for k in d.get('source_files', {}):
    if 'content' in d['source_files'][k]:
        d['source_files'][k]['content'] = '...(truncated)...'
if 'content' in d.get('incident_report', {}):
    d['incident_report']['content'] = '...(truncated)...'
print(json.dumps(d, indent=2, default=str))
" 2>/dev/null || cat /tmp/devtools_cascading_debug_result.json
