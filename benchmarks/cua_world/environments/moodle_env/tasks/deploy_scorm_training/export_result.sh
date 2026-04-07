#!/bin/bash
echo "=== Exporting SCORM Deployment Results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run a Python script inside the environment to safely extract the DB data and format as JSON
cat > /tmp/export_data.py << 'EOF'
import json
import subprocess
import os

def run_sql(query):
    try:
        with open("/tmp/mariadb_method", "r") as f:
            method = f.read().strip()
    except Exception:
        method = "native"

    if method == "docker":
        cmd = ['docker', 'exec', 'moodle-mariadb', 'mysql', '-u', 'moodleuser', '-pmoodlepass', 'moodle', '-N', '-B', '-e', query]
    else:
        cmd = ['mysql', '-u', 'moodleuser', '-pmoodlepass', 'moodle', '-N', '-B', '-e', query]
    
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except subprocess.CalledProcessError as e:
        return ""

# Read task metadata
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

try:
    with open('/tmp/target_course_id.txt', 'r') as f:
        course_id = int(f.read().strip())
except:
    course_id = 0

# 1. Query mdl_scorm
scorm_data_raw = run_sql(f"SELECT id, course, name, forcenewattempt, timemodified FROM mdl_scorm WHERE course={course_id} ORDER BY id DESC LIMIT 1")
scorm_created = False
scorm_name = ""
scorm_course = 0
forcenewattempt = 0
timemodified = 0

if scorm_data_raw:
    parts = scorm_data_raw.split('\t')
    if len(parts) >= 5:
        scorm_created = True
        scorm_course = int(parts[1])
        scorm_name = parts[2]
        forcenewattempt = int(parts[3])
        timemodified = int(parts[4])

# 2. Query Moodle's file API to verify the zip was actually uploaded to the module context
# Component: mod_scorm, Filearea: package
file_uploaded = False
filename = ""
filesize = 0

if scorm_created:
    file_query = """
    SELECT f.filename, f.filesize 
    FROM mdl_files f 
    JOIN mdl_context c ON f.contextid = c.id 
    JOIN mdl_course_modules cm ON c.instanceid = cm.id 
    JOIN mdl_modules m ON cm.module = m.id 
    WHERE m.name = 'scorm' 
      AND f.component = 'mod_scorm' 
      AND f.filearea = 'package' 
      AND f.filename != '.' 
    ORDER BY f.timecreated DESC LIMIT 1
    """
    file_data_raw = run_sql(file_query)
    if file_data_raw:
        parts = file_data_raw.split('\t')
        if len(parts) >= 2:
            filename = parts[0]
            filesize = int(parts[1])
            if filesize > 0 and filename.endswith('.zip'):
                file_uploaded = True

result = {
    "task_start": task_start,
    "course_id": course_id,
    "scorm_created": scorm_created,
    "scorm_name": scorm_name,
    "scorm_course": scorm_course,
    "forcenewattempt": forcenewattempt,
    "scorm_timemodified": timemodified,
    "file_uploaded": file_uploaded,
    "uploaded_filename": filename,
    "uploaded_filesize": filesize
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/export_data.py
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results JSON created:"
cat /tmp/task_result.json

echo "=== Export Complete ==="