#!/bin/bash
# Export script for Clinical Statistics Task
# Exports the agent's results table, view definition, and raw data for ground truth calculation

set -e

echo "=== Exporting Clinical Statistics Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Use Python for structured export
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "timestamp": datetime.datetime.now().isoformat(),
    "view_exists": False,
    "view_definition": "",
    "table_exists": False,
    "agent_results": {},
    "raw_data_dump": [],  # For ground truth calculation
    "error": None
}

try:
    conn = oracledb.connect(user="research", password="research123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check View Definition
    try:
        cursor.execute("SELECT text FROM user_views WHERE view_name = 'PATIENT_COHORTS_VW'")
        row = cursor.fetchone()
        if row:
            result["view_exists"] = True
            # View text might be a LOB
            result["view_definition"] = str(row[0])
    except Exception as e:
        print(f"View check error: {e}")

    # 2. Fetch Agent Results
    try:
        cursor.execute("SELECT metric_name, metric_value FROM study_results")
        rows = cursor.fetchall()
        if rows:
            result["table_exists"] = True
            for r in rows:
                # Key normalization: uppercase, strip
                key = str(r[0]).strip().upper()
                val = float(r[1]) if r[1] is not None else None
                result["agent_results"][key] = val
    except Exception as e:
        # Table might not exist
        print(f"Results table check error: {e}")

    # 3. Dump Raw Data (age, chol, thalach, diagnosis) for Ground Truth Calculation
    # We dump this to ensure the verifier calculates stats on EXACTLY what is in the DB
    cursor.execute("SELECT age, chol, thalach, diagnosis FROM heart_patients")
    raw_rows = cursor.fetchall()
    # Convert to list of dicts
    result["raw_data_dump"] = [
        {"age": r[0], "chol": r[1], "thalach": r[2], "diagnosis": r[3]} 
        for r in raw_rows
    ]

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = str(e)

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export completed to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="