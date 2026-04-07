#!/bin/bash
set -e
echo "=== Exporting Flaky Playwright Tests Result ==="

WORKSPACE_DIR="/home/ga/workspace/e2e_testing"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Best-effort VS Code save
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+s" 2>/dev/null || true
sleep 2

# Stop any running instances of the server
pkill -f "node server/app.js" || true
sleep 1

# Clear previous anti-gaming server logs
rm -f /tmp/server_activity.log

# We run the test suite twice with DIFFERENT network latencies to ensure flakiness is cured.
cd "$WORKSPACE_DIR"

echo "Running verification run 1 (Fast Network - 500ms)..."
sudo -u ga MAX_LATENCY=500 node server/app.js > /tmp/server_fast.log 2>&1 &
SRV1=$!
sleep 2
sudo -u ga npx playwright test --reporter=json > /tmp/report_500.json || true
kill $SRV1 || true
sleep 1

echo "Running verification run 2 (Slow Network - 3000ms)..."
sudo -u ga MAX_LATENCY=3000 node server/app.js > /tmp/server_slow.log 2>&1 &
SRV2=$!
sleep 2
sudo -u ga npx playwright test --reporter=json > /tmp/report_3000.json || true
kill $SRV2 || true

# Use Python to aggregate the Playwright JSON reports and Server logs into one clean output
python3 << 'EOF'
import json
import os

results = {}
for lat in [500, 3000]:
    report_path = f'/tmp/report_{lat}.json'
    if os.path.exists(report_path):
        try:
            with open(report_path, 'r') as f:
                data = json.load(f)
                for suite in data.get('suites', []):
                    for spec in suite.get('specs', []):
                        file_name = os.path.basename(spec.get('file', 'unknown'))
                        tests = spec.get('tests', [])
                        
                        ok = False
                        if tests and tests[0].get('results'):
                            # Playwright sets 'expected' when a test passes
                            ok = tests[0]['results'][0].get('status') == 'expected'
                        
                        if file_name not in results:
                            results[file_name] = []
                        results[file_name].append(ok)
        except Exception as e:
            print(f"Error parsing {report_path}: {e}")

logs = []
try:
    with open('/tmp/server_activity.log', 'r') as f:
        logs = f.read().splitlines()
except:
    pass

# Check modified files timestamps
task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

modified_files = []
tests_dir = "/home/ga/workspace/e2e_testing/tests"
if os.path.exists(tests_dir):
    for filename in os.listdir(tests_dir):
        if filename.endswith(".spec.js"):
            filepath = os.path.join(tests_dir, filename)
            mtime = os.path.getmtime(filepath)
            if mtime > task_start:
                modified_files.append(filename)

final_data = {
    "test_results": results,
    "server_logs": logs,
    "modified_files": modified_files
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_data, f, indent=2)
EOF

echo "Result saved to $RESULT_FILE"
cat $RESULT_FILE
echo "=== Export complete ==="