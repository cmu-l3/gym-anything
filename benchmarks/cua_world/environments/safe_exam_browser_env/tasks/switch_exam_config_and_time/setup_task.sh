#!/bin/bash
echo "=== Setting up switch_exam_config_and_time task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Inject scenario data into database
python3 << 'PYEOF'
import subprocess

def db_query(query):
    res = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True
    )
    return res.stdout.strip()

# Get Institution ID
inst_id = db_query("SELECT id FROM institution LIMIT 1")
if not inst_id:
    inst_id = "1"

# Create Configs
dummy_xml = '<?xml version="1.0" encoding="UTF-8"?><seb></seb>'
for cfg in ['Standard Secure Config', 'Calculator Permitted Config']:
    exists = db_query(f"SELECT id FROM configuration_node WHERE name='{cfg}' AND type='EXAM_CONFIG'")
    if not exists:
        db_query(f"INSERT INTO configuration_node (creationDate, name, description, institution_id, type, data, enabled) VALUES (NOW(), '{cfg}', 'Task Config', {inst_id}, 'EXAM_CONFIG', '{dummy_xml}', 1)")

cfg_old = db_query("SELECT id FROM configuration_node WHERE name='Standard Secure Config' AND type='EXAM_CONFIG' ORDER BY id DESC LIMIT 1")

# Create Exam
exam_exists = db_query("SELECT id FROM exam WHERE name='Intro to Psychology 101'")
if exam_exists:
    db_query(f"UPDATE exam SET configuration_id={cfg_old}, begindate='2026-06-15 09:00:00', enddate='2026-06-15 12:00:00' WHERE id={exam_exists}")
else:
    db_query(f"INSERT INTO exam (creationDate, name, description, institution_id, configuration_id, begindate, enddate, active) VALUES (NOW(), 'Intro to Psychology 101', 'Final Exam for PSY101', {inst_id}, {cfg_old}, '2026-06-15 09:00:00', '2026-06-15 12:00:00', 1)")
PYEOF

# Record baseline state for anti-gaming (capture initial enddate and config)
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT configuration_id, enddate FROM exam WHERE name='Intro to Psychology 101'" > /tmp/initial_exam_state.txt

# Launch Firefox and navigate to SEB Server
launch_firefox "http://localhost:8080"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="