#!/bin/bash
echo "=== Exporting Fix Database Migrations Result ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/workspace/media_db"
RESULT_FILE="/tmp/migration_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Execute an independent verification step to prevent gaming the local DB
# We will copy the agent's Alembic configuration to a temporary isolated environment
echo "Running isolated verification..."
sudo -u ga python3 << 'PYEVAL'
import json
import sqlite3
import subprocess
import os
import shutil

workspace = "/home/ga/workspace/media_db"
verify_dir = "/tmp/verify_db"
if os.path.exists(verify_dir):
    shutil.rmtree(verify_dir)
os.makedirs(verify_dir)

# Copy agent's alembic directory and ini
shutil.copytree(os.path.join(workspace, "alembic"), os.path.join(verify_dir, "alembic"))
shutil.copy(os.path.join(workspace, "alembic.ini"), os.path.join(verify_dir, "alembic.ini"))

# Setup pristine database via the generator script
shutil.copy(os.path.join(workspace, "create_db.py"), os.path.join(verify_dir, "create_db.py"))
os.chdir(verify_dir)
subprocess.run(["python3", "create_db.py"], check=True)

result_data = {
    "upgrade_success": False,
    "upgrade_stdout": "",
    "upgrade_stderr": "",
    "downgrade_success": False,
    "downgrade_stdout": "",
    "downgrade_stderr": "",
    "db_state_post_upgrade": {},
    "db_state_post_downgrade": {},
    "migration_script_content": ""
}

# Grab script content
script_path = os.path.join(verify_dir, "alembic", "versions", "a1b2c3d4_update_schema.py")
try:
    with open(script_path, "r") as f:
        result_data["migration_script_content"] = f.read()
except Exception:
    pass

# Run Upgrade
up_res = subprocess.run(["alembic", "upgrade", "head"], capture_output=True, text=True)
result_data["upgrade_success"] = (up_res.returncode == 0)
result_data["upgrade_stdout"] = up_res.stdout
result_data["upgrade_stderr"] = up_res.stderr

# Introspect Post-Upgrade DB
conn = sqlite3.connect("chinook.db")
c = conn.cursor()
try:
    cols = [col[1] for col in c.execute("PRAGMA table_info(Customer)").fetchall()]
    result_data["db_state_post_upgrade"]["customer_columns"] = cols
except Exception:
    pass

try:
    c.execute("SELECT COUNT(*) FROM Invoice WHERE InvoiceYear = 2009")
    result_data["db_state_post_upgrade"]["invoice_2009_count"] = c.fetchone()[0]
except Exception:
    result_data["db_state_post_upgrade"]["invoice_2009_count"] = -1

try:
    fks = c.execute("PRAGMA foreign_key_list(CustomerLog)").fetchall()
    result_data["db_state_post_upgrade"]["customerlog_fks"] = fks
except Exception:
    result_data["db_state_post_upgrade"]["customerlog_fks"] = []
    
conn.close()

# Run Downgrade
down_res = subprocess.run(["alembic", "downgrade", "base"], capture_output=True, text=True)
result_data["downgrade_success"] = (down_res.returncode == 0)
result_data["downgrade_stdout"] = down_res.stdout
result_data["downgrade_stderr"] = down_res.stderr

# Introspect Post-Downgrade DB
conn = sqlite3.connect("chinook.db")
c = conn.cursor()
try:
    cols = [col[1] for col in c.execute("PRAGMA table_info(Customer)").fetchall()]
    result_data["db_state_post_downgrade"]["customer_columns"] = cols
except Exception:
    pass

try:
    tables = [t[0] for t in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    result_data["db_state_post_downgrade"]["tables"] = tables
except Exception:
    pass

conn.close()

# Write results
with open("/tmp/migration_result.json", "w") as f:
    json.dump(result_data, f, indent=2)
PYEVAL

echo "Result saved to /tmp/migration_result.json"
echo "=== Export complete ==="