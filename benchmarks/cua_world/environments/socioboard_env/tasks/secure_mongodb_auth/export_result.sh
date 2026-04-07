#!/bin/bash
echo "=== Exporting secure_mongodb_auth result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract application and database state using Python
python3 << 'PYEOF'
import json, subprocess, glob, os

result = {}

# 1. Test unauthenticated access (Should FAIL if task is successful)
cmd_unauth = ["mongosh", "socioboard", "--eval", "db.init_collection.findOne()", "--quiet"]
proc_unauth = subprocess.run(cmd_unauth, capture_output=True, text=True)
result["unauth_output"] = proc_unauth.stdout + proc_unauth.stderr
result["unauth_exit_code"] = proc_unauth.returncode

# 2. Test authenticated access (Should SUCCEED if task is successful)
cmd_auth = [
    "mongosh", "socioboard", 
    "-u", "socioboard", 
    "-p", "SecureMongo2026!", 
    "--authenticationDatabase", "socioboard", 
    "--eval", "db.init_collection.findOne()", 
    "--quiet"
]
proc_auth = subprocess.run(cmd_auth, capture_output=True, text=True)
result["auth_output"] = proc_auth.stdout + proc_auth.stderr
result["auth_exit_code"] = proc_auth.returncode

# 3. Read microservice configuration files
result["configs"] = {}
for f in glob.glob('/opt/socioboard/socioboard-api/*/config/development.json'):
    service = os.path.basename(os.path.dirname(os.path.dirname(f)))
    try:
        with open(f, 'r') as fp:
            result["configs"][service] = json.load(fp)
    except Exception as e:
        result["configs"][service] = {"error": str(e)}

# 4. Get PM2 Status
try:
    proc_pm2 = subprocess.run(["pm2", "jlist"], capture_output=True, text=True)
    result["pm2_jlist"] = json.loads(proc_pm2.stdout)
except Exception as e:
    result["pm2_jlist"] = []

# 5. Get recent PM2 logs
try:
    proc_logs = subprocess.run(["pm2", "logs", "--nostream", "--lines", "100"], capture_output=True, text=True)
    result["pm2_logs"] = proc_logs.stdout + proc_logs.stderr
except Exception as e:
    result["pm2_logs"] = ""

# Write JSON output
with open("/tmp/task_result.json", "w") as fp:
    json.dump(result, fp, indent=2)
PYEOF

# Ensure file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "State exported to /tmp/task_result.json"
echo "=== Export complete ==="