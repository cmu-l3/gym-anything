#!/bin/bash
echo "=== Setting up create_patient_letter task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Use Python to set up the exact database state required safely
python3 << 'PYEOF'
import pymysql
import sys

try:
    conn = pymysql.connect(host='localhost', user='freemed', password='freemed', db='freemed')
    with conn.cursor() as cursor:
        # 1. Ensure Maria Santos exists
        cursor.execute("SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos'")
        patient = cursor.fetchone()
        
        if not patient:
            print("Patient Maria Santos not found. Creating...")
            cursor.execute("""
                INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) 
                VALUES ('Maria', 'Santos', '1978-06-22', 2)
            """)
            conn.commit()
            print("Patient created successfully.")
        else:
            print(f"Patient Maria Santos exists with ID: {patient[0]}")
            
        # 2. Find the correct letter table name (usually 'letter' but sometimes 'letters' depending on FreeMED version schema)
        cursor.execute("SHOW TABLES LIKE 'letter%'")
        tables = [row[0] for row in cursor.fetchall()]
        
        target_table = None
        if 'letter' in tables:
            target_table = 'letter'
        elif 'letters' in tables:
            target_table = 'letters'
            
        if target_table:
            with open('/tmp/letter_table_name', 'w') as f:
                f.write(target_table)
                
            cursor.execute(f"SELECT COUNT(*) FROM {target_table}")
            initial_count = cursor.fetchone()[0]
            
            cursor.execute(f"SELECT MAX(id) FROM {target_table}")
            max_id = cursor.fetchone()[0] or 0
            
            with open('/tmp/initial_letter_count', 'w') as f:
                f.write(str(initial_count))
            with open('/tmp/initial_max_letter_id', 'w') as f:
                f.write(str(max_id))
            print(f"Table '{target_table}' found. Initial count: {initial_count}, Max ID: {max_id}")
        else:
            print("WARNING: Could not find letter table in schema!")
            
except Exception as e:
    print(f"Database setup error: {e}", file=sys.stderr)
PYEOF

# Ensure FreeMED is running and focused in Firefox
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Click on center of screen to ensure desktop interaction is active
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 0.5

# Refocus Firefox
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="