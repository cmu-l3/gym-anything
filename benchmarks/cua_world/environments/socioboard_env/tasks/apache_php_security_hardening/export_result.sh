#!/bin/bash
echo "=== Exporting Security Hardening Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We use a Python script to reliably execute curl checks and export robust JSON
python3 << 'PYEOF'
import json
import subprocess
import os
import time

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout
    except subprocess.TimeoutExpired:
        return ""
    except Exception as e:
        return str(e)

print("Gathering HTTP headers...")
headers_raw = run_cmd("curl -s -I http://localhost/")

server_header = ""
x_powered_by = ""
for line in headers_raw.splitlines():
    if line.lower().startswith("server:"):
        server_header = line.split(":", 1)[1].strip()
    if line.lower().startswith("x-powered-by:"):
        x_powered_by = line.split(":", 1)[1].strip()

print("Testing directory browsing...")
test_idx_raw = run_cmd("curl -s -i http://localhost/test_indexes/")
test_idx_code = 0
if test_idx_raw and test_idx_raw.startswith("HTTP/"):
    try:
        test_idx_code = int(test_idx_raw.split(" ")[1])
    except:
        pass

print("Testing homepage health...")
home_raw = run_cmd("curl -s -I http://localhost/")
home_code = 0
if home_raw and home_raw.startswith("HTTP/"):
    try:
        home_code = int(home_raw.split(" ")[1])
    except:
        pass

# Check if Apache service is actually running
apache_running = False
ps_output = run_cmd("ps -ef | grep apache2 | grep -v grep")
if "apache2" in ps_output:
    apache_running = True

# Read timestamps for anti-gaming (ensure files were actually modified)
security_conf_mtime = 0
php_ini_mtime = 0
if os.path.exists("/etc/apache2/conf-enabled/security.conf"):
    security_conf_mtime = os.path.getmtime("/etc/apache2/conf-enabled/security.conf")
if os.path.exists("/etc/php/7.4/apache2/php.ini"):
    php_ini_mtime = os.path.getmtime("/etc/php/7.4/apache2/php.ini")

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        start_time = float(f.read().strip())
except:
    start_time = 0

data = {
    "server_header": server_header,
    "x_powered_by_header": x_powered_by,
    "test_indexes_code": test_idx_code,
    "test_indexes_body_snippet": test_idx_raw[:500] if test_idx_raw else "",
    "home_code": home_code,
    "apache_running": apache_running,
    "security_conf_modified_during_task": security_conf_mtime > start_time,
    "php_ini_modified_during_task": php_ini_mtime > start_time,
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

# Write output safely
temp_path = "/tmp/security_result_temp.json"
final_path = "/tmp/task_result.json"

with open(temp_path, "w") as f:
    json.dump(data, f, indent=2)

os.system(f"sudo mv {temp_path} {final_path}")
os.system(f"sudo chmod 666 {final_path}")

print("Result JSON saved.")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="