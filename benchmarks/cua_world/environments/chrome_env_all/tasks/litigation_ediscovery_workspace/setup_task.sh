#!/usr/bin/env bash
set -euo pipefail

echo "=== Litigation E-Discovery Workspace Setup ==="

# 1. Kill any running Chrome to modify profile data safely
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 1
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 2. Prepare directories and files
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/TechCorp_Case"
chown -R ga:ga /home/ga/.config/google-chrome/
chown -R ga:ga /home/ga/Documents/TechCorp_Case/

cat > /home/ga/Desktop/case_workspace_protocol.txt << 'EOF'
=== TECHCORP E-DISCOVERY WORKSPACE PROTOCOL ===
Ensure this shared workstation is fully sanitized from the prior "Globex" matter and configured for the TechCorp trial prep.

REQUIREMENTS:
1. BOOKMARKS: Organize legal bookmarks into exactly 3 folders on the Bookmark Bar:
   - "Court Dockets"
   - "Legal Research"
   - "E-Discovery"
2. PERSONAL BOOKMARKS: Delete all personal/entertainment bookmarks left by the previous user.
3. DATA SANITIZATION: Delete all Browsing History and Cookies associated with "globex".
   *CRITICAL*: Do NOT wipe all data. We need to preserve the generic legal research history/cookies for reference.
4. SEARCH SHORTCUTS: Add two custom search engines:
   - Keyword: usc -> URL: https://www.law.cornell.edu/uscode/text/%s
   - Keyword: scholar -> URL: https://scholar.google.com/scholar?q=%s
5. SECURE DOWNLOADS: Set the download location to ~/Documents/TechCorp_Case and enable "Ask where to save each file before downloading".
6. CREDENTIALS: Disable "Offer to save passwords" and "Save and fill addresses".
7. EXPORT: Export the finalized bookmarks to an HTML file saved at ~/Desktop/TechCorp_Bookmarks.html for the trial team.
EOF
chown ga:ga /home/ga/Desktop/case_workspace_protocol.txt

# 3. Create Bookmarks JSON (32 flat entries)
python3 << 'PYEOF'
import json, uuid, os

legal_urls = [
    ("PACER", "https://pacer.uscourts.gov/"), ("CourtListener", "https://www.courtlistener.com/"), 
    ("US Courts", "https://www.uscourts.gov/"), ("Supreme Court", "https://www.supremecourt.gov/"),
    ("Westlaw", "https://1.next.westlaw.com/"), ("LexisNexis", "https://advance.lexis.com/"),
    ("Cornell LII", "https://www.law.cornell.edu/"), ("Google Scholar", "https://scholar.google.com/"),
    ("Justia", "https://www.justia.com/"), ("Oyez", "https://www.oyez.org/"),
    ("Relativity", "https://www.relativity.com/"), ("Logikcull", "https://www.logikcull.com/"),
    ("Everlaw", "https://www.everlaw.com/"), ("DISCO", "https://www.csdisco.com/"),
    ("Clio", "https://www.clio.com/"), ("MyCase", "https://www.mycase.com/"),
    ("Fastcase", "https://www.fastcase.com/"), ("Casetext", "https://casetext.com/"),
    ("HeinOnline", "https://heinonline.org/"), ("Bloomberg Law", "https://pro.bloomberglaw.com/"),
    ("Reveal Data", "https://www.revealdata.com/"), ("Nuix", "https://www.nuix.com/")
]

personal_urls = [
    ("Facebook", "https://www.facebook.com/"), ("Netflix", "https://www.netflix.com/"),
    ("Pinterest", "https://www.pinterest.com/"), ("Etsy", "https://www.etsy.com/"),
    ("Buzzfeed", "https://www.buzzfeed.com/"), ("Instagram", "https://www.instagram.com/"),
    ("Hulu", "https://www.hulu.com/"), ("Reddit", "https://www.reddit.com/"),
    ("TikTok", "https://www.tiktok.com/"), ("Twitter", "https://www.twitter.com/")
]

children = []
for i, (name, url) in enumerate(legal_urls + personal_urls):
    children.append({
        "date_added": "13360000000000000",
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {"children": children, "date_added": "13360000000000000", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": "13360000000000000", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": "13360000000000000", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga /home/ga/.config/google-chrome/Default/Bookmarks

# 4. Inject History and Cookies
# First, quickly start/stop Chrome headless to initialize valid DB schemas
sudo -u ga google-chrome-stable --headless --disable-gpu --dump-dom https://example.com > /dev/null 2>&1 || true
sleep 2

python3 << 'PYEOF'
import sqlite3, time, os

def get_chrome_time(offset_days=0):
    return int((time.time() - (offset_days * 86400) + 11644473600) * 1000000)

profile_dir = "/home/ga/.config/google-chrome/Default"
history_db = os.path.join(profile_dir, "History")

# Inject History
try:
    conn = sqlite3.connect(history_db)
    c = conn.cursor()
    # 20 Globex entries
    for i in range(20):
        c.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time) VALUES (?, ?, ?, ?, ?)",
                  (f"https://intranet.globex.local/doc_{i}", f"Globex Corporate {i}", 1, 0, get_chrome_time(i)))
    # 40 Legal entries
    for i in range(40):
        c.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time) VALUES (?, ?, ?, ?, ?)",
                  (f"https://scholar.google.com/case_{i}", f"Legal Research {i}", 1, 0, get_chrome_time(i)))
    conn.commit()
    conn.close()
except Exception as e:
    print(f"History injection failed: {e}")

# Inject Cookies (Try both Network/Cookies and Cookies paths for version compatibility)
cookies_db = os.path.join(profile_dir, "Network", "Cookies")
if not os.path.exists(os.path.dirname(cookies_db)):
    os.makedirs(os.path.dirname(cookies_db), exist_ok=True)

try:
    conn = sqlite3.connect(cookies_db)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS cookies (creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, top_frame_site_key TEXT NOT NULL DEFAULT '', name TEXT NOT NULL, value TEXT NOT NULL, encrypted_value BLOB DEFAULT '', path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL DEFAULT 1, samesite INTEGER NOT NULL DEFAULT -1, source_scheme INTEGER NOT NULL DEFAULT 0, source_port INTEGER NOT NULL DEFAULT -1, is_same_party INTEGER NOT NULL DEFAULT 0, last_update_utc INTEGER NOT NULL DEFAULT 0, source_type INTEGER NOT NULL DEFAULT 0, has_cross_site_ancestor INTEGER NOT NULL DEFAULT 1)''')
    
    # 8 Globex cookies
    for i in range(8):
        c.execute("INSERT INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent) VALUES (?, ?, '', ?, 'val', '/', ?, 1, 1, ?, 1, 1)",
                  (get_chrome_time(), ".globex.local", f"sess_{i}", get_chrome_time(-1), get_chrome_time()))
    # 15 Legal cookies
    for i in range(15):
        c.execute("INSERT INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent) VALUES (?, ?, '', ?, 'val', '/', ?, 1, 1, ?, 1, 1)",
                  (get_chrome_time(), ".lexisnexis.com", f"pref_{i}", get_chrome_time(-1), get_chrome_time()))
    conn.commit()
    conn.close()
except Exception as e:
    print(f"Cookie injection failed: {e}")
PYEOF
chown -R ga:ga /home/ga/.config/google-chrome/

# Record anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 5. Start Chrome for the user
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable about:blank &"
sleep 5

DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="