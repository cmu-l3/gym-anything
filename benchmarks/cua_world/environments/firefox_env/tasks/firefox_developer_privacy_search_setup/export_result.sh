#!/bin/bash
echo "=== Exporting Firefox Developer Privacy & Search Setup Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take a final screenshot as visual evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# CRITICAL: Gracefully stop Firefox to flush prefs.js and places.sqlite to disk!
echo "Stopping Firefox to flush databases..."
pkill -f firefox 2>/dev/null || true
sleep 5

# Force kill if it's still hanging
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Run a Python script to extract data safely from Firefox configuration files
python3 << 'EOF'
import sqlite3
import json
import os

profile_dir = "/home/ga/.mozilla/firefox/default.profile"
db_path = os.path.join(profile_dir, "places.sqlite")
prefs_path = os.path.join(profile_dir, "prefs.js")

result = {
    "tracking_protection": "unknown",
    "do_not_track": False,
    "keywords": [],
    "bookmarks": [],
    "db_exists": os.path.exists(db_path),
    "prefs_exists": os.path.exists(prefs_path)
}

# Parse prefs.js for privacy settings
if os.path.exists(prefs_path):
    with open(prefs_path, 'r', encoding='utf-8') as f:
        for line in f:
            if "browser.contentblocking.category" in line:
                if '"strict"' in line: 
                    result["tracking_protection"] = "strict"
                elif '"standard"' in line: 
                    result["tracking_protection"] = "standard"
                elif '"custom"' in line: 
                    result["tracking_protection"] = "custom"
            if "privacy.donottrackheader.enabled" in line and "true" in line:
                result["do_not_track"] = True

# Parse places.sqlite for keywords and bookmarks
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        # Extract custom search keywords
        c.execute("SELECT keyword, url FROM moz_keywords k JOIN moz_places p ON k.place_id = p.id")
        result["keywords"] = [{"keyword": row[0], "url": row[1]} for row in c.fetchall()]
        
        # Extract bookmarks (type = 1 means bookmark)
        c.execute("SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1")
        result["bookmarks"] = [{"title": row[0], "url": row[1]} for row in c.fetchall() if row[0]]
        
        conn.close()
    except Exception as e:
        result["db_error"] = str(e)

# Write to a temporary file, then move it to avoid permission issues
temp_path = "/tmp/result_temp.json"
with open(temp_path, "w") as f:
    json.dump(result, f, indent=2)

os.system(f"cp {temp_path} /tmp/task_result.json")
os.system(f"chmod 666 /tmp/task_result.json")
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="