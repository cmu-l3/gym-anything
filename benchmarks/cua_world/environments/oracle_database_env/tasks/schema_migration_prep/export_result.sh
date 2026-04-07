#!/bin/bash
# Export script for Schema Migration Prep task
# Verifies database objects and output files

echo "=== Exporting Schema Migration Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Execute Python verification script inside the environment
# using oracledb to check DB state and file I/O to check files
python3 << 'PYEOF'
import oracledb
import json
import os
import re

result = {
    "db_connection_ok": False,
    "backup_tables": {},
    "source_tables": {},
    "files": {},
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0))
}

# 1. Database Verification
try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    result["db_connection_ok"] = True

    # Check Backup Tables
    for table in ["BKP_EMPLOYEES", "BKP_DEPARTMENTS", "BKP_JOBS"]:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            result["backup_tables"][table] = {"exists": True, "count": count}
        except oracledb.DatabaseError:
            result["backup_tables"][table] = {"exists": False, "count": 0}

    # Check Source Tables (ensure not dropped/truncated)
    for table in ["EMPLOYEES", "DEPARTMENTS", "JOBS"]:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            result["source_tables"][table] = {"exists": True, "count": count}
        except oracledb.DatabaseError:
            result["source_tables"][table] = {"exists": False, "count": 0}

    cursor.close()
    conn.close()
except Exception as e:
    result["db_error"] = str(e)

# 2. File Verification
file_checks = {
    "ddl": "/home/ga/Desktop/hr_schema_ddl.sql",
    "manifest": "/home/ga/Desktop/migration_manifest.txt",
    "dependencies": "/home/ga/Desktop/dependency_report.txt"
}

for key, path in file_checks.items():
    file_info = {
        "exists": False,
        "size": 0,
        "created_during_task": False,
        "content_preview": "",
        "keywords_found": []
    }
    
    if os.path.exists(path):
        file_info["exists"] = True
        stats = os.stat(path)
        file_info["size"] = stats.st_size
        
        # Check creation time vs task start
        if stats.st_mtime > result["task_start"]:
            file_info["created_during_task"] = True
            
        # Read content for keywords
        try:
            with open(path, 'r', errors='ignore') as f:
                content = f.read()
                file_info["content_preview"] = content[:500]
                
                if key == "ddl":
                    if "CREATE TABLE" in content.upper(): file_info["keywords_found"].append("CREATE TABLE")
                    if "CREATE INDEX" in content.upper(): file_info["keywords_found"].append("CREATE INDEX")
                    if "EMPLOYEES" in content.upper(): file_info["keywords_found"].append("EMPLOYEES")
                elif key == "manifest":
                    if "TABLE" in content.upper(): file_info["keywords_found"].append("TABLE")
                    if "VALID" in content.upper() or "INVALID" in content.upper(): file_info["keywords_found"].append("STATUS")
                elif key == "dependencies":
                    if "REFERENCES" in content.upper() or "DEPEND" in content.upper(): file_info["keywords_found"].append("REFERENCES")
        except Exception as e:
            file_info["read_error"] = str(e)
            
    result["files"][key] = file_info

# Write Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="