#!/bin/bash
# export_result.sh for save_tor_pages_for_offline_research task

echo "=== Exporting save_tor_pages_for_offline_research results ==="

TASK_NAME="save_tor_pages_for_offline_research"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile to copy DB
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"

# Copy database to avoid lock issues
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Use Python to evaluate file contents, timestamps, and sqlite DB
python3 << 'PYEOF' > /tmp/${TASK_NAME}_script_output.txt
import os
import json
import sqlite3

TASK_NAME = "save_tor_pages_for_offline_research"
result = {
    "dir_exists": False,
    "tor_community": {"exists": False},
    "tor_metrics": {"exists": False},
    "tor_blog": {"exists": False},
    "bib_exists": False,
    "bib_header": False,
    "bib_has_community": False,
    "bib_has_metrics": False,
    "bib_has_blog": False,
    "history": {"community": False, "metrics": False, "blog": False}
}

try:
    with open(f"/tmp/{TASK_NAME}_start_ts", "r") as f:
        task_start = int(f.read().strip())
    result["task_start"] = task_start
except:
    task_start = 0
    result["task_start"] = 0

# Check directory
target_dir = "/home/ga/Documents/TorResearch"
if os.path.isdir(target_dir):
    result["dir_exists"] = True

# Helper to check HTML files
def check_html(fname, keyword):
    path = os.path.join(target_dir, fname)
    if not os.path.isfile(path):
        return {"exists": False}
    
    sz = os.path.getsize(path)
    mt = os.path.getmtime(path)
    
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read().lower()
        has_html = '<html' in content or '<!doctype' in content
        has_kw = keyword.lower() in content
    except Exception:
        has_html, has_kw = False, False
        
    return {
        "exists": True,
        "size": sz,
        "is_new": mt > task_start,
        "has_html": has_html,
        "has_keyword": has_kw
    }

if result["dir_exists"]:
    result["tor_community"] = check_html('tor-community.html', 'community')
    result["tor_metrics"] = check_html('tor-metrics.html', 'metrics')
    result["tor_blog"] = check_html('tor-blog.html', 'blog')

    # Check Bibliography
    bib_path = os.path.join(target_dir, 'bibliography.txt')
    if os.path.isfile(bib_path):
        result["bib_exists"] = True
        try:
            with open(bib_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            result["bib_header"] = 'bibliography' in content
            result["bib_has_community"] = 'community.torproject.org' in content
            result["bib_has_metrics"] = 'metrics.torproject.org' in content
            result["bib_has_blog"] = 'blog.torproject.org' in content
        except:
            pass

# Check Database
db_path = f"/tmp/{TASK_NAME}_places.sqlite"
if os.path.isfile(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places p JOIN moz_historyvisits h ON p.id = h.place_id")
        urls = [row[0].lower() for row in c.fetchall()]
        
        result["history"]["community"] = any('community.torproject.org' in u for u in urls)
        result["history"]["metrics"] = any('metrics.torproject.org' in u for u in urls)
        result["history"]["blog"] = any('blog.torproject.org' in u for u in urls)
    except Exception as e:
        result["db_error"] = str(e)

# Write final JSON output
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_script_output.txt 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json