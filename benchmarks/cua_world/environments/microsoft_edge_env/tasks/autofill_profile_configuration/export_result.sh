#!/bin/bash
# export_result.sh - Post-task hook for autofill_profile_configuration
# Exports the Web Data DB content and Preferences to JSON for verification

set -e
echo "=== Exporting Autofill Configuration Results ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure DB is flushed and unlocked
echo "Stopping Edge to release database locks..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 3. Paths
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
WEB_DATA_DB="/home/ga/.config/microsoft-edge/Default/Web Data"
RESULT_JSON="/tmp/task_result.json"

# 4. Run Python script to extract data safely
# We use a python script inside the container to handle SQLite and JSON parsing 
# robustly, ensuring we output a clean JSON for the verifier.

python3 -c "
import sqlite3
import json
import os
import shutil
import time

result = {
    'autofill_enabled': False,
    'profiles': [],
    'db_read_success': False,
    'prefs_read_success': False,
    'task_start_time': 0,
    'db_last_modified': 0
}

# Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start_time'] = int(f.read().strip())
except:
    pass

# --- CHECK PREFERENCES (Feature Toggle) ---
prefs_path = '$PREFS_FILE'
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
            # Check autofill.profile_enabled
            # Edge structure: autofill -> profile_enabled (bool)
            # Sometimes located in 'autofill' -> 'profile_enabled' or 'enabled' depending on version
            autofill_settings = prefs.get('autofill', {})
            # If key missing, default is usually True, but we want to confirm user didn't disable it
            # or explicitly enabled it if it was off.
            result['autofill_enabled'] = autofill_settings.get('profile_enabled', True)
            result['prefs_read_success'] = True
    except Exception as e:
        print(f'Error reading Preferences: {e}')

# --- CHECK WEB DATA (Profiles) ---
db_path = '$WEB_DATA_DB'
temp_db = '/tmp/web_data_export.db'

if os.path.exists(db_path):
    result['db_last_modified'] = os.path.getmtime(db_path)
    try:
        # Copy DB to temp to avoid locks
        shutil.copy2(db_path, temp_db)
        
        conn = sqlite3.connect(temp_db)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        
        # Query autofill_profiles
        # Schema varies slightly by version, but usually has:
        # guid, company_name, street_address_1, city, state, zipcode, date_modified
        # First Name/Last Name might be split or in 'fullname' depending on schema version.
        # Newer schemas use separate tables for names/emails/phones, but 'autofill_profiles'
        # often remains the anchor or a view. 
        # For robustness, we select * and map dynamically.
        
        cur.execute('SELECT * FROM autofill_profiles')
        rows = cur.fetchall()
        
        for row in rows:
            profile = dict(row)
            
            # Chromium stores timestamps as microseconds since 1601-01-01
            # Convert to unix timestamp for easier verification
            # Unix epoch (1970) is 11644473600 seconds after 1601
            if 'date_modified' in profile:
                micro_sec = profile['date_modified']
                unix_ts = (micro_sec / 1000000) - 11644473600
                profile['date_modified_unix'] = unix_ts
            
            # If names are in separate tables, we might need simple join logic,
            # but usually the main view contains enough.
            # Let's try to fetch separate name/email/phone if 'fullname' etc are missing
            guid = profile.get('guid')
            
            # Fetch Name if not present
            if 'first_name' not in profile:
                try:
                    cur.execute('SELECT first_name, last_name, full_name FROM autofill_profile_names WHERE guid=?', (guid,))
                    name_row = cur.fetchone()
                    if name_row:
                        profile.update(dict(name_row))
                except: pass

            # Fetch Email
            try:
                cur.execute('SELECT email FROM autofill_profile_emails WHERE guid=?', (guid,))
                email_rows = cur.fetchall()
                profile['emails'] = [r['email'] for r in email_rows]
            except: pass

            # Fetch Phone
            try:
                cur.execute('SELECT number FROM autofill_profile_phones WHERE guid=?', (guid,))
                phone_rows = cur.fetchall()
                profile['phones'] = [r['number'] for r in phone_rows]
            except: pass

            result['profiles'].append(profile)
            
        result['db_read_success'] = True
        conn.close()
        if os.path.exists(temp_db):
            os.remove(temp_db)
            
    except Exception as e:
        print(f'Error reading Web Data DB: {e}')

# Write Result
with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# 5. Fix permissions for copy_from_env
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="