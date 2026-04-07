#!/bin/bash
echo "=== Setting up link_exam_security_policies task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/task_initial.png /tmp/task_final.png 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Attempt to seed data directly via MySQL to save agent time
# If this fails (e.g. due to strict schema changes), the agent's instructions 
# inherently direct it to create the missing entities via the UI instead.
python3 << 'PYEOF'
import subprocess

def run_sql(sql):
    subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', sql], 
        check=False, stderr=subprocess.DEVNULL
    )

def query_sql(sql):
    res = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', sql], 
        capture_output=True, text=True
    )
    return res.stdout.strip()

try:
    inst_id = query_sql("SELECT id FROM institution LIMIT 1") or '1'
    
    # Pre-seed Template
    run_sql(f"INSERT IGNORE INTO exam_template (name, description, institution_id) VALUES ('High Security Template', 'Strict lockdown', {inst_id})")
    
    # Pre-seed Connection Config
    run_sql(f"INSERT IGNORE INTO seb_client_configuration (name, description, institution_id, active) VALUES ('Campus BYOD Config', 'For student devices', {inst_id}, 1)")
    
    # Pre-seed Exam
    run_sql(f"INSERT IGNORE INTO exam (name, status, institution_id) VALUES ('Physics 301 Midterm', 'CONSTRUCTION', {inst_id})")
    
    print("Database pre-seeding completed.")
except Exception as e:
    print(f"Data seed warning (agent will fallback to UI creation): {e}")
PYEOF

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Take initial screenshot showing the app is open
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="