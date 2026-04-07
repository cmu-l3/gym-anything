#!/bin/bash
echo "=== Exporting identity_document_compliance_setup result ==="

# Record task end time
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Robust Python script to dump Sentrifugo document tables regardless of exact schema variations
python3 << 'EOF'
import subprocess
import json
import time
import os

def run_query(sql):
    cmd = ["docker", "exec", "sentrifugo-db", "mysql", "-u", "root", "-prootpass123", "sentrifugo", "-N", "-B", "-e", sql]
    try:
        return subprocess.check_output(cmd, text=True).strip()
    except Exception as e:
        return ""

def get_table(table):
    cmd = ["docker", "exec", "sentrifugo-db", "mysql", "-u", "root", "-prootpass123", "sentrifugo", "-B", "-e", f"SELECT * FROM {table}"]
    try:
        out = subprocess.check_output(cmd, text=True).strip()
        if not out: return []
        lines = out.splitlines()
        headers = lines[0].split('\t')
        rows = []
        for line in lines[1:]:
            parts = line.split('\t')
            rows.append(dict(zip(headers, parts)))
        return rows
    except Exception:
        return []

try:
    # Get all users for employeeId mapping
    users = get_table("main_users")
    
    # Discover all tables in the database dynamically to handle schema updates/variations
    tables_out = run_query("SHOW TABLES;")
    all_tables = [t.strip() for t in tables_out.splitlines() if t.strip()]
    
    # Find global document configuration tables
    doc_config_tables = [t for t in all_tables if 'identity' in t.lower() and 'emp' not in t.lower()]
    if not doc_config_tables: 
        doc_config_tables = [t for t in all_tables if 'document' in t.lower() and 'emp' not in t.lower()]

    # Find employee document mapping tables
    doc_emp_tables = [t for t in all_tables if 'identity' in t.lower() and 'emp' in t.lower()]
    if not doc_emp_tables: 
        doc_emp_tables = [t for t in all_tables if 'document' in t.lower() and 'emp' in t.lower()]

    doc_types = []
    for t in doc_config_tables:
        doc_types.extend(get_table(t))
        
    emp_docs = []
    for t in doc_emp_tables:
        emp_docs.extend(get_table(t))
        
    # Get task start time for anti-gaming checks
    task_start = 0
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            content = f.read().strip()
            task_start = int(content) if content.isdigit() else 0

    result = {
        "task_start": task_start,
        "task_end": int(time.time()),
        "users": users,
        "doc_types": doc_types,
        "emp_docs": emp_docs
    }
    
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)
        
except Exception as e:
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": str(e)}, f)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="