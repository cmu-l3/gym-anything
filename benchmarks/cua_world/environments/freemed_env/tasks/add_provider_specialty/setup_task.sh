#!/bin/bash
# Setup task: add_provider_specialty
echo "=== Setting up add_provider_specialty task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Clean up any pre-existing records matching the expected taxonomy or specialty
# to ensure the agent has to create it from scratch.
echo "Purging any existing matching records to ensure clean state..."
python3 -c "
import mysql.connector
try:
    db = mysql.connector.connect(user='freemed', password='freemed', database='freemed', host='localhost')
    cursor = db.cursor()
    cursor.execute('SHOW TABLES')
    tables = [t[0] for t in cursor.fetchall()]
    for table in tables:
        try:
            cursor.execute(f'SHOW COLUMNS FROM \`{table}\`')
            cols = [c[0] for c in cursor.fetchall()]
            
            # Delete if taxonomy code or specialty name exists
            where_clauses = [f\"\`{c}\` LIKE '%207RG0100X%' OR \`{c}\` LIKE '%Gastroenterology%'\" for c in cols]
            if where_clauses:
                where_str = ' OR '.join(where_clauses)
                cursor.execute(f'DELETE FROM \`{table}\` WHERE {where_str}')
                db.commit()
        except Exception as e:
            pass
except Exception as e:
    print(f'DB setup warning: {e}')
" 2>/dev/null

# Ensure Firefox is running and navigated to FreeMED
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window to ensure agent can see full UI
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_specialty_start.png

echo ""
echo "=== add_provider_specialty task setup complete ==="
echo "Task: Add Specialty (Gastroenterology), Taxonomy (207RG0100X), Description (Digestive System Specialist)"
echo "Login: admin / admin"
echo ""