#!/bin/bash
echo "=== Setting up web_browser_artifact_triage task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/web_browser_result.json /tmp/web_browser_gt.json \
      /tmp/web_browser_start_time 2>/dev/null || true

for d in /home/ga/Cases/DarkWeb_Investigation_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Create Chrome Profile Logical Evidence ────────────────────────────────────
EVIDENCE_DIR="/home/ga/evidence/Chrome_Profile/Default"
mkdir -p "$EVIDENCE_DIR"
chown -R ga:ga /home/ga/evidence/Chrome_Profile 2>/dev/null || true

HISTORY_DB="$EVIDENCE_DIR/History"

# Attempt to download a realistic public-domain test Chrome History database
wget --timeout=15 -q -O "$HISTORY_DB" "https://raw.githubusercontent.com/obsidianforensics/hindsight/master/tests/fixtures/default_profile/History" 2>/dev/null || true

# If download fails or file is too small, generate an authentic SQLite structure fallback
python3 << PYEOF
import sqlite3, os
db_path = "$HISTORY_DB"

if not os.path.exists(db_path) or os.path.getsize(db_path) < 1000:
    print("Generating fallback Chrome History database...")
    if os.path.exists(db_path):
        os.remove(db_path)
    
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Minimal Chrome schema required for Autopsy's Recent Activity
    c.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)")
    c.execute("CREATE TABLE keyword_search_terms (keyword_id INTEGER NOT NULL, url_id INTEGER NOT NULL, lower_term LONGVARCHAR NOT NULL, term LONGVARCHAR NOT NULL)")
    c.execute("CREATE TABLE downloads (id INTEGER PRIMARY KEY, guid VARCHAR, current_path LONGVARCHAR, target_path LONGVARCHAR NOT NULL, start_time INTEGER NOT NULL, received_bytes INTEGER NOT NULL, total_bytes INTEGER NOT NULL, state INTEGER NOT NULL, danger_type INTEGER NOT NULL, interrupt_reason INTEGER NOT NULL, hash BLOB NOT NULL, end_time INTEGER NOT NULL, opened INTEGER NOT NULL, last_access_time INTEGER NOT NULL, transient INTEGER NOT NULL, referrer VARCHAR NOT NULL, site_url VARCHAR NOT NULL, tab_url VARCHAR NOT NULL, tab_referrer_url VARCHAR NOT NULL, http_method VARCHAR NOT NULL, by_ext_id VARCHAR NOT NULL, by_ext_name VARCHAR NOT NULL, etag VARCHAR NOT NULL, last_modified VARCHAR NOT NULL, mime_type VARCHAR(255) NOT NULL, original_mime_type VARCHAR(255) NOT NULL)")

    # Insert suspicious realistic web searches
    c.execute("INSERT INTO urls VALUES (1, 'https://www.google.com/search?q=how+to+hide+assets', 'how to hide assets - Google Search', 1, 0, 13245678900000000, 0)")
    c.execute("INSERT INTO keyword_search_terms VALUES (1, 1, 'how to hide assets', 'how to hide assets')")
    c.execute("INSERT INTO urls VALUES (2, 'https://www.google.com/search?q=offshore+bank+accounts+no+kyc', 'offshore bank accounts no kyc - Google Search', 1, 0, 13245678910000000, 0)")
    c.execute("INSERT INTO keyword_search_terms VALUES (2, 2, 'offshore bank accounts no kyc', 'offshore bank accounts no kyc')")
    c.execute("INSERT INTO urls VALUES (3, 'https://www.google.com/search?q=buy+monero+anonymously', 'buy monero anonymously - Google Search', 1, 0, 13245678920000000, 0)")
    c.execute("INSERT INTO keyword_search_terms VALUES (3, 3, 'buy monero anonymously', 'buy monero anonymously')")

    # Insert suspicious realistic downloads
    c.execute("INSERT INTO downloads VALUES (1, 'guid1', '/home/user/Downloads/tails-amd64-5.8.iso', '/home/user/Downloads/tails-amd64-5.8.iso', 13245678900000000, 1200000000, 1200000000, 1, 0, 0, X'00', 13245678950000000, 0, 13245678900000000, 0, 'https://tails.boum.org/', 'https://tails.boum.org/', 'https://tails.boum.org/', '', 'GET', '', '', '', '', 'application/x-iso9660-image', 'application/x-iso9660-image')")
    c.execute("INSERT INTO downloads VALUES (2, 'guid2', '/home/user/Downloads/VeraCrypt_Setup_x64_1.25.9.exe', '/home/user/Downloads/VeraCrypt_Setup_x64_1.25.9.exe', 13245678910000000, 35000000, 35000000, 1, 0, 0, X'00', 13245678920000000, 0, 13245678910000000, 0, 'https://www.veracrypt.fr/', 'https://www.veracrypt.fr/', 'https://www.veracrypt.fr/', '', 'GET', '', '', '', '', 'application/x-msdownload', 'application/x-msdownload')")
    c.execute("INSERT INTO downloads VALUES (3, 'guid3', '/home/user/Downloads/bleachbit_4.4.2_all_ubuntu2004.deb', '/home/user/Downloads/bleachbit_4.4.2_all_ubuntu2004.deb', 13245678930000000, 200000, 200000, 1, 0, 0, X'00', 13245678940000000, 0, 13245678930000000, 0, 'https://www.bleachbit.org/', 'https://www.bleachbit.org/', 'https://www.bleachbit.org/', '', 'GET', '', '', '', '', 'application/vnd.debian.binary-package', 'application/vnd.debian.binary-package')")
    
    conn.commit()
    conn.close()
    print("Fallback database created.")
PYEOF

chown ga:ga "$HISTORY_DB" 2>/dev/null || true

# ── Extract Ground Truth Directly from SQLite ─────────────────────────────────
echo "Pre-computing ground truth from History SQLite database..."
python3 << PYEOF
import sqlite3, json, os

db_path = "$HISTORY_DB"
gt = {
    "searches": [],
    "downloads": [],
    "total_searches": 0,
    "total_downloads": 0
}

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    c = conn.cursor()
    
    # Extract searches
    c.execute("SELECT term FROM keyword_search_terms")
    searches = [row[0] for row in c.fetchall()]
    gt["searches"] = searches
    gt["total_searches"] = len(searches)
    
    # Extract downloads
    c.execute("SELECT target_path FROM downloads")
    # Store just the filenames to handle different OS path formats robustly
    downloads = [os.path.basename(row[0]) for row in c.fetchall()]
    gt["downloads"] = downloads
    gt["total_downloads"] = len(downloads)
    
    conn.close()
except Exception as e:
    print(f"Error extracting GT: {e}")

with open("/tmp/web_browser_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth Extracted: {gt['total_searches']} searches, {gt['total_downloads']} downloads")
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/web_browser_start_time

# ── Kill any running Autopsy and relaunch ─────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false
while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "FATAL: Autopsy Welcome screen did NOT appear."
    exit 1
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial evidence screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="