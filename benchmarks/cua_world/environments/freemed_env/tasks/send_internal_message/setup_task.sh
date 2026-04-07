#!/bin/bash
echo "=== Setting up send_internal_message task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# 1. Ensure patient Maria Santos exists
echo "Ensuring patient Maria Santos exists..."
EXISTING_PT=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Maria' AND ptlname='Santos'" 2>/dev/null || echo "0")
if [ "${EXISTING_PT:-0}" -eq 0 ]; then
    freemed_query "INSERT INTO patient (ptfname, ptlname) VALUES ('Maria', 'Santos');" 2>/dev/null || true
fi

# 2. Ensure user Sarah Mitchell (smitchell) exists
echo "Ensuring recipient user smitchell exists..."
EXISTING_USER=$(freemed_query "SELECT COUNT(*) FROM user WHERE username='smitchell'" 2>/dev/null || echo "0")
if [ "${EXISTING_USER:-0}" -eq 0 ]; then
    freemed_query "INSERT INTO user (username, userpassword, userdescrip, usertype, userfname, userlname) VALUES ('smitchell', MD5('password'), 'Nurse', 'usr', 'Sarah', 'Mitchell');" 2>/dev/null || true
fi

# 3. Clean up any pre-existing messages containing the target text to prevent gaming
echo "Cleaning up pre-existing target messages..."
python3 -c "
import mysql.connector
try:
    conn = mysql.connector.connect(host='localhost', user='freemed', password='freemed', database='freemed')
    cursor = conn.cursor(dictionary=True)
    target = '%lipid panel is back%'
    
    # Clean message tables
    cursor.execute(\"SHOW TABLES LIKE '%message%'\")
    for row in cursor.fetchall():
        table = list(row.values())[0]
        cursor.execute(f\"SHOW COLUMNS FROM {table}\")
        for col_row in cursor.fetchall():
            if 'text' in col_row['Type'].lower() or 'char' in col_row['Type'].lower():
                cursor.execute(f\"DELETE FROM {table} WHERE {col_row['Field']} LIKE %s\", (target,))
                conn.commit()
                
    # Clean pnotes
    cursor.execute(\"SHOW TABLES LIKE 'pnotes'\")
    if cursor.fetchall():
        cursor.execute(\"SHOW COLUMNS FROM pnotes\")
        for col_row in cursor.fetchall():
            if 'text' in col_row['Type'].lower() or 'char' in col_row['Type'].lower():
                cursor.execute(f\"DELETE FROM pnotes WHERE {col_row['Field']} LIKE %s\", (target,))
                conn.commit()
except Exception as e:
    print(f'Cleanup warning: {e}')
" 2>/dev/null || true

# 4. Launch browser
echo "Launching FreeMED..."
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start.png

echo ""
echo "=== send_internal_message task setup complete ==="