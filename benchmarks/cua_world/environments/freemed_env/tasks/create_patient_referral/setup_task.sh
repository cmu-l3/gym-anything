#!/bin/bash
# Setup task: create_patient_referral
# Pre-loads Patient: Elena Rodriguez
# Pre-loads Providers: Sarah Chen (Family Medicine), James Wilson (Cardiology)

echo "=== Setting up create_patient_referral task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 1. Ensure patient Elena Rodriguez exists
freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex, ptaddr1, ptcity, ptstate, ptzip) SELECT 'Elena', 'Rodriguez', '1968-07-22', 'f', '2847 Oak Valley Drive', 'Springfield', 'IL', '62704' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM patient WHERE ptfname='Elena' AND ptlname='Rodriguez');" 2>/dev/null
ELENA_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Elena' AND ptlname='Rodriguez' LIMIT 1" 2>/dev/null)

# 2. Ensure referring and specialist providers exist
freemed_query "INSERT INTO physician (phylname, phyfname, phytitle, physpecialty, phynpi) SELECT 'Chen', 'Sarah', 'Dr.', 'Family Medicine', '1234567890' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM physician WHERE phylname='Chen' AND phyfname='Sarah');" 2>/dev/null
freemed_query "INSERT INTO physician (phylname, phyfname, phytitle, physpecialty, phynpi) SELECT 'Wilson', 'James', 'Dr.', 'Cardiology', '0987654321' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM physician WHERE phylname='Wilson' AND phyfname='James');" 2>/dev/null
CHEN_ID=$(freemed_query "SELECT id FROM physician WHERE phylname='Chen' AND phyfname='Sarah' LIMIT 1" 2>/dev/null)
WILSON_ID=$(freemed_query "SELECT id FROM physician WHERE phylname='Wilson' AND phyfname='James' LIMIT 1" 2>/dev/null)

# Save entity IDs for the export script to use
echo "$ELENA_ID" > /tmp/patient_id
echo "$CHEN_ID" > /tmp/chen_id
echo "$WILSON_ID" > /tmp/wilson_id

# 3. Find the exact referral table name dynamically and record initial state
# FreeMED modules can use various table names (e.g., referral, referrals)
python3 -c "
import mysql.connector
try:
    conn = mysql.connector.connect(user='freemed', password='freemed', database='freemed')
    cursor = conn.cursor()
    cursor.execute(\"SHOW TABLES LIKE '%referral%'\")
    tables = cursor.fetchall()
    if tables:
        table = tables[0][0]
        cursor.execute(f\"SELECT COUNT(*), MAX(id) FROM {table}\")
        row = cursor.fetchone()
        count = row[0]
        max_id = row[1] if row[1] is not None else 0
        with open('/tmp/ref_table_info.txt', 'w') as f:
            f.write(f\"{table},{count},{max_id}\")
    else:
        with open('/tmp/ref_table_info.txt', 'w') as f:
            f.write(\"none,0,0\")
except Exception as e:
    with open('/tmp/ref_table_info.txt', 'w') as f:
        f.write(\"none,0,0\")
" 2>/dev/null || echo "none,0,0" > /tmp/ref_table_info.txt

# 4. Launch UI and maximize
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Capture initial state evidence
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== create_patient_referral task setup complete ==="