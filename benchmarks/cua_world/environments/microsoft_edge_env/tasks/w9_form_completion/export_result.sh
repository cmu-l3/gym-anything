#!/bin/bash
# Export script for W-9 Form Completion task

echo "=== Exporting W-9 Form Result ==="

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TARGET_FILE="/home/ga/Documents/Acme_W9_Filled.pdf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze the PDF and History
python3 << PYEOF
import json
import os
import sqlite3
import shutil
import time
import sys

# Try importing pypdf
try:
    from pypdf import PdfReader
    PYPDF_AVAILABLE = True
except ImportError:
    PYPDF_AVAILABLE = False

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "file_size": 0,
    "irs_visited": False,
    "field_data": {},
    "pdf_parsable": False,
    "pypdf_installed": PYPDF_AVAILABLE
}

target_file = "${TARGET_FILE}"
task_start = ${TASK_START}

# 1. Check File Stats
if os.path.exists(target_file):
    result["file_exists"] = True
    stat = os.stat(target_file)
    result["file_size"] = stat.st_size
    # Check modification time
    if stat.st_mtime > task_start:
        result["file_created_during_task"] = True

    # 2. Parse PDF Content if available
    if PYPDF_AVAILABLE and result["file_size"] > 0:
        try:
            reader = PdfReader(target_file)
            fields = reader.get_fields()
            
            # Extract relevant fields (W-9 field names can vary slightly by revision, 
            # so we grab specific keys or dump all for the verifier to inspect)
            extracted = {}
            if fields:
                for key, value in fields.items():
                    # Get the value object
                    val = value.get('/V', '')
                    # Handle indirect objects if necessary (pypdf usually handles simple form fields)
                    extracted[key] = str(val) if val else ""
            
            result["field_data"] = extracted
            result["pdf_parsable"] = True
        except Exception as e:
            print(f"PDF parsing error: {e}")
            result["pdf_error"] = str(e)

# 3. Check Browser History for IRS visit
history_path = "/home/ga/.config/microsoft-edge/Default/History"
if os.path.exists(history_path):
    try:
        # Copy to temp to avoid lock
        shutil.copy2(history_path, "/tmp/history_check.db")
        conn = sqlite3.connect("/tmp/history_check.db")
        cursor = conn.cursor()
        # Look for visits to irs.gov
        cursor.execute("SELECT count(*) FROM urls WHERE url LIKE '%irs.gov%'")
        count = cursor.fetchone()[0]
        if count > 0:
            result["irs_visited"] = True
        conn.close()
        os.remove("/tmp/history_check.db")
    except Exception as e:
        print(f"History check error: {e}")

# Save result
with open("/tmp/w9_task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/w9_task_result.json 2>/dev/null || true

echo "Result saved to /tmp/w9_task_result.json"
cat /tmp/w9_task_result.json 2>/dev/null || echo "Error reading result file"

echo "=== Export complete ==="