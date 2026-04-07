#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Telehealth Session Workspace Task ==="

# Record task start time (anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Stop Chrome to safely generate profile data
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Setup Directories
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/Patient_Handouts"

# Create standard operating procedure document
cat > "/home/ga/Desktop/telehealth_browser_standard.txt" << 'EOF'
TELEHEALTH BROWSER CONFIGURATION STANDARD
=========================================

1. BOOKMARK ORGANIZATION
   Create these 3 folders on the bookmark bar and sort the clinical links into them:
   - "Clinical Portals" (SimplePractice, Doxy.me, Theranest, CareCloud, MDToolbox)
   - "Patient Education" (Mayo Clinic, NAMI, NIMH, SAMHSA, Psychology Today, HelpGuide)
   - "Crisis Resources" (988 Lifeline, Crisis Text Line, Trevor Project, Veterans Crisis Line, Domestic Violence Hotline)
   DELETE all personal/entertainment bookmarks from the browser completely.

2. HISTORY SANITIZATION
   Delete all browsing history associated with personal domains (Netflix, Amazon, Facebook, Twitter, Reddit, YouTube, Pinterest, Instagram, Spotify).
   DO NOT clear all history. History for clinical domains must be preserved for compliance.

3. WEBRTC (CAMERA/MIC) PERMISSIONS
   Navigate to Site Settings -> Camera and Microphone.
   Add "https://doxy.me" to the explicit "Allowed to use" list for both camera and microphone.
   This ensures counselors are never prompted during a crisis session.

4. SEARCH & PRIVACY
   - Create a site search shortcut with keyword "dsm" pointing to: https://www.psychiatryonline.org/action/doSearch?AllField=%s
   - Disable password saving and address autofill.
   - Set the default download location to ~/Documents/Patient_Handouts.

5. CONFIRMATION
   Create a text file at ~/Desktop/setup_complete.txt containing the exact text:
   Telehealth setup verified
EOF

# Python script to generate Bookmarks JSON and History SQLite database natively
python3 << 'PYEOF'
import json
import sqlite3
import time
import os
import uuid

chrome_profile = "/home/ga/.config/google-chrome/Default"

# Chrome timestamps are microseconds since 1601-01-01 UTC
chrome_base = int((time.time() + 11644473600) * 1000000)

clinical_sites = [
    ("SimplePractice", "https://www.simplepractice.com/"),
    ("Doxy.me", "https://doxy.me/"),
    ("Theranest", "https://theranest.com/"),
    ("EHR CareCloud", "https://ehr.carecloud.com/"),
    ("MDToolbox", "https://mdtoolbox.net/"),
    ("Mayo Clinic", "https://www.mayoclinic.org/"),
    ("NAMI", "https://www.nami.org/"),
    ("NIMH", "https://www.nimh.nih.gov/"),
    ("SAMHSA", "https://www.samhsa.gov/"),
    ("Psychology Today", "https://www.psychologytoday.com/"),
    ("HelpGuide", "https://www.helpguide.org/"),
    ("988 Suicide & Crisis Lifeline", "https://988lifeline.org/"),
    ("Crisis Text Line", "https://www.crisistextline.org/"),
    ("The Trevor Project", "https://www.thetrevorproject.org/"),
    ("Veterans Crisis Line", "https://www.veteranscrisisline.net/"),
    ("National Domestic Violence Hotline", "https://www.thehotline.org/")
]

personal_sites = [
    ("Netflix", "https://www.netflix.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Twitter", "https://twitter.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("YouTube", "https://www.youtube.com/"),
    ("Pinterest", "https://www.pinterest.com/"),
    ("Instagram", "https://www.instagram.com/"),
    ("Spotify", "https://open.spotify.com/")
]

all_sites = clinical_sites + personal_sites

# 1. GENERATE BOOKMARKS
children = []
for i, (name, url) in enumerate(all_sites):
    children.append({
        "date_added": str(chrome_base - (i * 10000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base),
            "date_modified": str(chrome_base),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(os.path.join(chrome_profile, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)

# 2. GENERATE HISTORY DB
db_path = os.path.join(chrome_profile, "History")
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Minimum schema to be recognized by Chrome without wiping
c.execute("CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)")
c.execute("INSERT INTO meta VALUES ('version','58')")
c.execute("INSERT INTO meta VALUES ('last_compatible_version','16')")
c.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)")
c.execute("CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0, segment_id INTEGER, visit_duration INTEGER DEFAULT 0, incremented_omnibox_typed INTEGER DEFAULT 0)")

for i, (name, url) in enumerate(all_sites * 3):  # Create multiple visits
    visit_time = chrome_base - (i * 3600000000) # Past hours
    c.execute('INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)', (url, name, visit_time))
    url_id = c.lastrowid
    c.execute('INSERT INTO visits (url, visit_time, transition) VALUES (?, ?, 805306368)', (url_id, visit_time))

conn.commit()
conn.close()
PYEOF

# Ensure proper ownership
chown -R ga:ga /home/ga/.config/google-chrome/
chown -R ga:ga /home/ga/Documents/Patient_Handouts
chown ga:ga /home/ga/Desktop/telehealth_browser_standard.txt

# Start Chrome to lock profile and initialize any missing internal files
su - ga -c "DISPLAY=:1 google-chrome-stable > /dev/null 2>&1 &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="