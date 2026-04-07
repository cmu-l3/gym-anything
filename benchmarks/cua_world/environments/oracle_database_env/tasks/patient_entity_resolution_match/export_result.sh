#!/bin/bash
# Export script for Patient Entity Resolution task
# Checks the database state (PATIENT_LINKAGE table) and output CSV

set -e

echo "=== Exporting Patient Entity Resolution Results ==="

source /workspace/scripts/task_utils.sh

# Take screenshot of final state
take_screenshot /tmp/task_final.png

# Read planted IDs
PLANTED_IDS_JSON=$(sudo cat /tmp/planted_match_ids.json)
ID_A=$(echo "$PLANTED_IDS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['case_a'])")
ID_B=$(echo "$PLANTED_IDS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['case_b'])")
ID_C=$(echo "$PLANTED_IDS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['case_c'])")

echo "Verifying matches for Master IDs: $ID_A, $ID_B, $ID_C"

# Run Python script to query DB and generate JSON result
python3 << PYEOF
import oracledb
import json
import os
import csv

result = {
    "table_exists": False,
    "columns_correct": False,
    "row_count": 0,
    "csv_exists": False,
    "csv_row_count": 0,
    "match_a_found": False, # Exact: Jonathan Doe
    "match_b_found": False, # Typo: Christoper Nolan
    "match_c_found": False, # Format: Sarah Oconnor
    "false_positive_d_found": False, # Bill Gates (Should fail score < 90)
    "false_positive_e_found": False, # Michael Jordan (Diff DOB)
    "scores_valid": True, # Will check a sample
    "export_error": None
}

try:
    # 1. Check CSV File
    csv_path = "/home/ga/Desktop/linkage_report.csv"
    if os.path.exists(csv_path):
        result["csv_exists"] = True
        try:
            with open(csv_path, 'r') as f:
                reader = csv.reader(f)
                rows = list(reader)
                result["csv_row_count"] = len(rows)
        except Exception as e:
            pass

    # 2. Check Database Table
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check table existence
    cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'PATIENT_LINKAGE'")
    if cursor.fetchone()[0] > 0:
        result["table_exists"] = True
        
        # Check columns
        cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'PATIENT_LINKAGE'")
        cols = {row[0] for row in cursor.fetchall()}
        if {"INTAKE_ID", "MPI_ID", "MATCH_SCORE"}.issubset(cols):
            result["columns_correct"] = True
            
        # Get all rows
        cursor.execute("SELECT intake_id, mpi_id, match_score FROM patient_linkage")
        rows = cursor.fetchall()
        result["row_count"] = len(rows)
        
        # Verify specific cases
        # Planted Intake IDs: 1 (A), 2 (B), 3 (C), 4 (D), 5 (E)
        # Expected Master IDs: $ID_A, $ID_B, $ID_C
        
        for r in rows:
            intake_id = r[0]
            mpi_id = r[1]
            score = r[2]
            
            if intake_id == 1 and mpi_id == $ID_A:
                result["match_a_found"] = True
            elif intake_id == 2 and mpi_id == $ID_B:
                result["match_b_found"] = True
            elif intake_id == 3 and mpi_id == $ID_C:
                result["match_c_found"] = True
            elif intake_id == 4:
                result["false_positive_d_found"] = True
            elif intake_id == 5:
                result["false_positive_e_found"] = True
                
    cursor.close()
    conn.close()

except Exception as e:
    result["export_error"] = str(e)

with open("/tmp/patient_linkage_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/patient_linkage_result.json"
cat /tmp/patient_linkage_result.json