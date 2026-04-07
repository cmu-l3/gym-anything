#!/bin/bash
echo "=== Setting up bulk_activate_semester_exams task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Seed the database with the required exams
echo "Seeding exams into database..."
cat << 'PYEOF' > /tmp/seed_exams.py
import pymysql
import sys

try:
    conn = pymysql.connect(host='127.0.0.1', user='root', password='sebserver123', database='SEBServer', autocommit=True)
    with conn.cursor(pymysql.cursors.DictCursor) as c:
        # Check columns to safely insert
        c.execute("SHOW COLUMNS FROM exam")
        cols = [r['Field'] for r in c.fetchall()]
        
        # Get an institution id to link to
        c.execute("SELECT id FROM institution LIMIT 1")
        inst_row = c.fetchone()
        inst_id = inst_row['id'] if inst_row else 1
        
        # Clean up any potential conflicting names from previous runs
        c.execute("DELETE FROM exam WHERE name LIKE 'Spring 2026%' OR name LIKE 'Fall 2025%'")
        
        exams = [
            ('Spring 2026: Biology 101', 'Task Data'),
            ('Spring 2026: Chemistry 201', 'Task Data'),
            ('Spring 2026: Calculus I', 'Task Data'),
            ('Spring 2026: Physics 301 [DEPRECATED]', 'Do not activate'),
            ('Fall 2025: History 101', 'Old exam')
        ]
        
        for name, desc in exams:
            query = "INSERT INTO exam (name, description"
            values = f"('{name}', '{desc}'"
            
            if 'institution_id' in cols:
                query += ", institution_id"
                values += f", {inst_id}"
                
            if 'active' in cols:
                query += ", active"
                values += ", 0"
            elif 'status' in cols:
                query += ", status"
                values += ", 'INACTIVE'"
                
            query += ") VALUES " + values + ")"
            c.execute(query)
            
    print("Exams seeded successfully.")
except Exception as e:
    print(f"Error seeding database: {e}")
    sys.exit(1)
PYEOF

# Run inside docker if necessary or directly
docker exec -i seb-server-mariadb python3 < /tmp/seed_exams.py || python3 /tmp/seed_exams.py || echo "Warning: Seeding script failed, task might not have data."

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="