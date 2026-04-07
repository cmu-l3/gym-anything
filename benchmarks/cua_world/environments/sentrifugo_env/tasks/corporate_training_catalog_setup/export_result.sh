#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 2. Extract database state reliably via Python inside the container
cat > /tmp/export_db.py << 'EOF'
import json
import subprocess
import time
import os

def query_to_dicts(query):
    cmd = f'docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "{query}" -B'
    try:
        out = subprocess.check_output(cmd, shell=True, text=True).strip()
        if not out: return []
        lines = out.split('\n')
        if len(lines) < 2: return []
        headers = lines[0].split('\t')
        results = []
        for line in lines[1:]:
            results.append(dict(zip(headers, line.split('\t'))))
        return results
    except Exception as e:
        return [{"error": str(e)}]

def main():
    providers = query_to_dicts("SELECT * FROM main_trainingproviders WHERE isactive=1")
    if len(providers) > 0 and "error" in providers[0]:
        providers = query_to_dicts("SELECT * FROM main_training_providers WHERE isactive=1")
        
    courses = query_to_dicts("SELECT * FROM main_trainingcourses WHERE isactive=1")
    if len(courses) > 0 and "error" in courses[0]:
        courses = query_to_dicts("SELECT * FROM main_training_courses WHERE isactive=1")

    # Read start timestamp
    task_start = 0
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            try: task_start = int(f.read().strip())
            except: pass

    result = {
        "providers": providers,
        "courses": courses,
        "task_start": task_start,
        "task_end": int(time.time()),
        "app_was_running": True
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
EOF

python3 /tmp/export_db.py
chmod 666 /tmp/task_result.json

echo "Result JSON exported."
cat /tmp/task_result.json
echo "=== Export complete ==="