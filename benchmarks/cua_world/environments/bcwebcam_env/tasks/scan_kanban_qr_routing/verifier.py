#!/usr/bin/env python3
"""
Verifier for scan_kanban_qr_routing task.

Verifies that the agent correctly extracted data from a dynamically 
generated QR code image and appended it to a CSV file while preserving 
the integrity of historical records.
"""

import json
import os
import tempfile
import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scan_kanban_qr_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    csv_exists = result.get("csv_exists", False)
    csv_modified = result.get("csv_modified", False)
    csv_content = result.get("csv_content", [])
    
    expected_part = str(result.get("expected_part", ""))
    expected_qty = str(result.get("expected_qty", ""))
    expected_cell = str(result.get("expected_cell", ""))
    expected_urgent = str(result.get("expected_urgent", ""))

    if not csv_exists:
        return {"passed": False, "score": 0, "feedback": "Target CSV file no longer exists. Agent may have deleted it."}

    if not csv_modified:
        feedback.append("File modification timestamps indicate the CSV file was NOT modified.")
    else:
        feedback.append("CSV file was modified successfully.")

    # Remove empty lines that might occur during bad agent appends
    csv_content = [line for line in csv_content if line.strip()]

    # 1. Proper Append Check (20 pts)
    # The setup created exactly 4 rows (1 header + 3 data). 
    # A correct append makes it exactly 5 rows.
    if len(csv_content) == 5:
        score += 20
        feedback.append("[+20] Exactly one new row was appended.")
    elif len(csv_content) > 5:
        score += 10
        feedback.append(f"[+10] New rows were appended, but found {len(csv_content)} total rows instead of 5.")
    else:
        feedback.append(f"[+0] Expected 5 total rows, found {len(csv_content)}. Row was not appended correctly.")

    # 2. File Integrity Check (20 pts)
    expected_history = [
        "DateScanned,PartNumber,RequestedQuantity,SourceWorkcell,IsUrgent",
        "2025-10-01,AX-9910-B,50,ASM-05,NO",
        "2025-10-02,RM-4421-C,200,PKG-01,YES",
        "2025-10-03,QW-1102-X,15,MCH-04,NO"
    ]

    integrity_passed = True
    if len(csv_content) >= 4:
        for i in range(4):
            # Normalize strings by stripping whitespace and standardizing commas
            if csv_content[i].strip() != expected_history[i].strip():
                integrity_passed = False
                feedback.append(f"Historical row {i} was corrupted or modified. Expected: '{expected_history[i]}'")
                break
        
        if integrity_passed:
            score += 20
            feedback.append("[+20] File integrity preserved (Header and historical data untouched).")
    else:
        integrity_passed = False
        feedback.append("Historical data rows were deleted or corrupted.")

    # 3. Data Extraction and Date Format Evaluation
    data_accurate = False
    
    if len(csv_content) >= 5:
        last_row = csv_content[-1].strip().split(',')
        if len(last_row) >= 5:
            date_scanned = last_row[0].strip()
            part_num = last_row[1].strip()
            qty = last_row[2].strip()
            cell = last_row[3].strip()
            urgent = last_row[4].strip()

            # Date Format (20 pts)
            try:
                datetime.datetime.strptime(date_scanned, "%Y-%m-%d")
                score += 20
                feedback.append(f"[+20] Correct date format detected: {date_scanned}")
            except ValueError:
                feedback.append(f"[+0] Invalid date format or missing date: '{date_scanned}'. Expected YYYY-MM-DD.")

            # Data Extraction (40 pts)
            if (part_num == expected_part and 
                qty == expected_qty and 
                cell == expected_cell and 
                urgent == expected_urgent):
                score += 40
                data_accurate = True
                feedback.append("[+40] Accurate data extraction from KANBAN QR payload mapping perfectly to CSV columns.")
            else:
                feedback.append(f"[+0] Data extraction mismatch. Expected: {expected_part},{expected_qty},{expected_cell},{expected_urgent}. Got: {part_num},{qty},{cell},{urgent}")
        else:
            feedback.append("The appended row did not contain the correct 5 comma-separated columns.")

    # Pass Condition: Must get at least 80 points AND correctly map the dynamic payload
    passed = (score >= 80) and data_accurate

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }