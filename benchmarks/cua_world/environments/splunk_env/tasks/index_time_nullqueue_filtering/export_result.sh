#!/bin/bash
echo "=== Exporting index_time_nullqueue_filtering results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Ensure Splunk is running, otherwise we can't test
if ! splunk_is_running; then
    echo "Splunk is not running. Starting it so we can run verification tests..."
    sudo /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Run the python script to generate test data, ingest it, and evaluate
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

sudo python3 - << "PYEOF" > "$TEMP_JSON"
import sys, json, subprocess, uuid, time, os

uuid_a = str(uuid.uuid4())
uuid_b = str(uuid.uuid4())

log_content = f"""May 12 10:00:00 server sshd[123]: Accepted publickey for user admin [{uuid_a}]
May 12 10:01:00 server CRON[456]: (root) CMD (/usr/bin/task) [{uuid_b}]
"""
with open('/tmp/verify_syslog.log', 'w') as f:
    f.write(log_content)

# Ingest test file
subprocess.run([
    '/opt/splunk/bin/splunk', 'add', 'oneshot', '/tmp/verify_syslog.log', 
    '-index', 'system_logs', '-sourcetype', 'syslog', '-auth', 'admin:SplunkAdmin1!'
], capture_output=True)

# Wait for indexing to complete
time.sleep(12)

# Query UUID A (Expected to be indexed)
res_a = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/services/search/jobs', 
     '--data-urlencode', f'search=search index=system_logs "{uuid_a}"', 
     '-d', 'exec_mode=oneshot', '-d', 'output_mode=json'], 
    capture_output=True, text=True
)
count_a = 0
try:
    count_a = len(json.loads(res_a.stdout).get('results', []))
except Exception:
    pass

# Query UUID B (Expected to be dropped/nullQueue)
res_b = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/services/search/jobs', 
     '--data-urlencode', f'search=search index=system_logs "{uuid_b}"', 
     '-d', 'exec_mode=oneshot', '-d', 'output_mode=json'], 
    capture_output=True, text=True
)
count_b = 0
try:
    count_b = len(json.loads(res_b.stdout).get('results', []))
except Exception:
    pass

# Extract Btool configurations
btool_transforms = subprocess.run(['/opt/splunk/bin/splunk', 'cmd', 'btool', 'transforms', 'list'], capture_output=True, text=True).stdout
btool_props = subprocess.run(['/opt/splunk/bin/splunk', 'cmd', 'btool', 'props', 'list', 'syslog'], capture_output=True, text=True).stdout

# Get file modification times
def get_mtime(path):
    try:
        return int(os.path.getmtime(path))
    except:
        return 0

props_mtime = get_mtime('/opt/splunk/etc/system/local/props.conf')
transforms_mtime = get_mtime('/opt/splunk/etc/system/local/transforms.conf')

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

out = {
    "uuid_a_count": count_a,
    "uuid_b_count": count_b,
    "btool_transforms": btool_transforms,
    "btool_props_syslog": btool_props,
    "props_mtime": props_mtime,
    "transforms_mtime": transforms_mtime,
    "task_start_time": task_start
}
print(json.dumps(out))
PYEOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="