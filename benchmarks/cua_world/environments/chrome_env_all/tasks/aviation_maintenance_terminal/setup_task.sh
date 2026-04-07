#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Aviation Maintenance Terminal task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Stop any running Chrome instances cleanly
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# Create target directories
mkdir -p /home/ga/Documents/C_Check_Manuals
chown ga:ga /home/ga/Documents/C_Check_Manuals

# Prepare checklist document
cat > /home/ga/Desktop/terminal_prep_checklist.txt << 'EOF'
MAINTENANCE TERMINAL PREP CHECKLIST
===================================
1. DATA SANITIZATION
   [ ] Clear all Browsing History (All time)
   [ ] Clear all Cookies and other site data (All time)
   [ ] Delete non-work bookmarks (YouTube, Reddit, ESPN)

2. BOOKMARK ORGANIZATION
   Create these 4 folders on the Bookmark Bar and sort the aviation links:
   [ ] Airframe (Boeing, Airbus, Bombardier)
   [ ] Powerplant (GE, Pratt & Whitney, Rolls-Royce)
   [ ] Avionics (Garmin, Honeywell, Rockwell)
   [ ] Regulatory (FAA, EASA, NTSB)

3. SITE EXCEPTIONS (Privacy and security > Site settings)
   [ ] Allow Pop-ups for: https://drs.faa.gov
   [ ] Allow Pop-ups for: https://techdocs.boeing.com
   [ ] Allow Insecure content for: http://maint-server.local

4. BROWSER PREFERENCES
   [ ] Set Homepage to: http://maint-server.local
   [ ] Change Download location to: /home/ga/Documents/C_Check_Manuals
   [ ] Disable "Ask where to save each file before downloading" toggle
EOF
chown ga:ga /home/ga/Desktop/terminal_prep_checklist.txt

# Create Chrome Profile and Inject Data via Python
python3 << 'PYEOF'
import sqlite3, os, time, json

profile_dir = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_dir, exist_ok=True)

# 1. Inject History (45 entries)
hist_path = os.path.join(profile_dir, "History")
if os.path.exists(hist_path):
    os.remove(hist_path)
conn = sqlite3.connect(hist_path)
c = conn.cursor()
c.execute('''CREATE TABLE urls (id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)''')
now_micro = int(time.time() * 1000000)
for i in range(45):
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)", (f"https://example.com/old_shift_data_{i}", f"Old Shift Page {i}", now_micro))
conn.commit()
conn.close()

# 2. Inject Cookies (30 entries)
cookie_path = os.path.join(profile_dir, "Cookies")
if os.path.exists(cookie_path):
    os.remove(cookie_path)
conn = sqlite3.connect(cookie_path)
c = conn.cursor()
c.execute('''CREATE TABLE cookies (creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, top_frame_site_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, encrypted_value BLOB DEFAULT '', path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL DEFAULT 1, samesite INTEGER NOT NULL DEFAULT -1, source_scheme INTEGER NOT NULL DEFAULT 0, source_port INTEGER NOT NULL DEFAULT -1, is_same_party INTEGER NOT NULL DEFAULT 0, last_update_utc INTEGER NOT NULL)''')
for i in range(30):
    c.execute("INSERT INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, last_update_utc) VALUES (?, ?, '', ?, 'val', '/', 0, 0, 0, 0, 0, 0, 0)", (now_micro, f".old-shift-{i}.com", f"session_id_{i}"))
conn.commit()
conn.close()

# 3. Create Bookmarks
bookmarks = {
    "checksum": "initial_state",
    "roots": {
        "bookmark_bar": {
            "children": [
                {"id": "11", "name": "Boeing TechDocs", "type": "url", "url": "https://techdocs.boeing.com"},
                {"id": "12", "name": "Airbus World", "type": "url", "url": "https://w3.airbus.com"},
                {"id": "13", "name": "Bombardier Portal", "type": "url", "url": "https://businessaircraft.bombardier.com"},
                {"id": "14", "name": "GE Aerospace", "type": "url", "url": "https://www.geaerospace.com"},
                {"id": "15", "name": "Pratt & Whitney", "type": "url", "url": "https://www.prattwhitney.com"},
                {"id": "16", "name": "Rolls-Royce Care", "type": "url", "url": "https://care.rolls-royce.com"},
                {"id": "17", "name": "Garmin Aviation", "type": "url", "url": "https://fly.garmin.com"},
                {"id": "18", "name": "Honeywell Aerospace", "type": "url", "url": "https://aerospace.honeywell.com"},
                {"id": "19", "name": "Rockwell Collins", "type": "url", "url": "https://www.rockwellcollins.com"},
                {"id": "20", "name": "FAA DRS", "type": "url", "url": "https://drs.faa.gov"},
                {"id": "21", "name": "EASA", "type": "url", "url": "https://www.easa.europa.eu"},
                {"id": "22", "name": "NTSB Aviation", "type": "url", "url": "https://www.ntsb.gov/aviation"},
                {"id": "23", "name": "YouTube", "type": "url", "url": "https://www.youtube.com"},
                {"id": "24", "name": "Reddit", "type": "url", "url": "https://www.reddit.com"},
                {"id": "25", "name": "ESPN", "type": "url", "url": "https://www.espn.com"}
            ],
            "date_added": "13360000000000000",
            "date_modified": "0",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        }
    },
    "version": 1
}
with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f)
PYEOF
chown -R ga:ga /home/ga/.config/google-chrome

# Launch Chrome to a blank tab
su - ga -c "DISPLAY=:1 google-chrome-stable about:blank > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="