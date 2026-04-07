#!/bin/bash
echo "=== Exporting Segregate Vendor Contacts result ==="

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot before closing app
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close Thunderbird to flush database writes
echo "Closing Thunderbird to flush DB..."
su - ga -c "DISPLAY=:1 wmctrl -c 'Address Book'" 2>/dev/null || true
su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
sleep 3
pkill -f "thunderbird" 2>/dev/null || true
sleep 1

# Python script to analyze the Address Book state
cat > /tmp/export_contacts.py << 'EOF'
import os
import json
import sqlite3
import re

profile_dir = "/home/ga/.thunderbird/default-release"
prefs_path = os.path.join(profile_dir, "prefs.js")

ext_filename = None
ext_book_created = False

# 1. Parse prefs.js to find the new address book mapping
if os.path.exists(prefs_path):
    with open(prefs_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        # Regex to find: user_pref("ldap_2.servers.X.description", "External Vendors");
        match = re.search(r'user_pref\("ldap_2\.servers\.([^"]+)\.description",\s*"External Vendors"\);', content)
        if match:
            ext_book_created = True
            server_id = match.group(1)
            # Regex to find: user_pref("ldap_2.servers.X.filename", "abook-1.sqlite");
            file_match = re.search(rf'user_pref\("ldap_2\.servers\.{server_id}\.filename",\s*"([^"]+)"\);', content)
            if file_match:
                ext_filename = file_match.group(1)

def get_emails(db_name):
    emails = []
    db_path = os.path.join(profile_dir, db_name)
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        try:
            # Depending on Thunderbird version, contacts are in properties or cards
            c.execute("SELECT value FROM properties WHERE name='PrimaryEmail'")
            emails = [row[0].lower().strip() for row in c.fetchall() if row[0]]
        except Exception:
            pass
        finally:
            conn.close()
    return emails

# 2. Read personal address book
personal_emails = get_emails("abook.sqlite")

# 3. Read External Vendors address book
ext_emails = get_emails(ext_filename) if ext_filename else []

result = {
    "task_start": int(os.environ.get('TASK_START', 0)),
    "task_end": int(os.environ.get('TASK_END', 0)),
    "ext_book_created": ext_book_created,
    "ext_book_filename": ext_filename,
    "personal_emails": personal_emails,
    "ext_emails": ext_emails
}

# Dump to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

export TASK_START TASK_END
python3 /tmp/export_contacts.py

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="