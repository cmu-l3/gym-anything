#!/bin/bash
# Export script for redo_log_sizing_optimization task
# Exports the final configuration of Redo Logs

echo "=== Exporting Redo Log Configuration ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/redo_log_final_screenshot.png

# Export Redo Log data using Python
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "final_groups": [],
    "total_groups": 0,
    "sizes_bytes": [],
    "statuses": [],
    "file_paths": [],
    "commands_executed": [],
    "timestamp": datetime.datetime.now().isoformat(),
    "error": None
}

try:
    # Connect as SYSTEM
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Get Log Group Info
    cursor.execute("SELECT group#, bytes, status, members FROM v$log ORDER BY group#")
    rows = cursor.fetchall()
    
    result["total_groups"] = len(rows)
    for r in rows:
        result["final_groups"].append({
            "group": r[0],
            "bytes": r[1],
            "status": r[2],
            "members": r[3]
        })
        result["sizes_bytes"].append(r[1])
        result["statuses"].append(r[2])

    # 2. Get Log File Paths
    cursor.execute("SELECT group#, member FROM v$logfile")
    files = cursor.fetchall()
    for f in files:
        result["file_paths"].append(f[1])

    # 3. Check v$sql for evidence of work (Anti-gaming)
    # Looking for ALTER DATABASE ADD/DROP LOGFILE commands executed by the user
    cursor.execute("""
        SELECT sql_text 
        FROM v$sql 
        WHERE (UPPER(sql_text) LIKE '%ADD LOGFILE%' OR UPPER(sql_text) LIKE '%DROP LOGFILE%')
          AND UPPER(sql_text) NOT LIKE '%V$SQL%'
    """)
    sqls = cursor.fetchall()
    result["commands_executed"] = [s[0] for s in sqls]

except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/redo_log_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported result to /tmp/redo_log_result.json")
PYEOF

# Validate output exists
if [ -f "/tmp/redo_log_result.json" ]; then
    echo "Export successful."
    cat /tmp/redo_log_result.json
else
    echo "Export failed."
    exit 1
fi