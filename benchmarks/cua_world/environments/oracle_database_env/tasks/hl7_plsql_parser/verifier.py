#!/usr/bin/env python3
"""
Verifier for HL7 PL/SQL Parser task.

Critera:
1. Target table PATIENT_ADMISSIONS exists with correct structure (10 pts)
2. PL/SQL Procedure exists and is VALID (15 pts)
3. Row count matches source (~100 rows) (15 pts)
4. Sentinel Record Data Accuracy (60 pts total):
   - MRN extracted correctly (10 pts)
   - Name formatted 'Last, First' (15 pts)
   - Event extracted 'ADT^A01' (10 pts)
   - Date parsed correctly to Oracle DATE object (15 pts)
   - Diagnosis code extracted (10 pts)

Pass Threshold: 65 points
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_parser(traj, env_info, task_info):
    """
    Verify the HL7 parsing task based on database state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('sentinel_name_expected', 'Everdeen, Katniss')
    expected_event = metadata.get('sentinel_event', 'ADT^A01')
    expected_diag = metadata.get('sentinel_diagnosis', 'J01.90')

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Table Existence (10)
    if result.get("table_exists") and result.get("columns_correct"):
        score += 10
        feedback_parts.append("Table created with correct columns")
    elif result.get("table_exists"):
        score += 5
        feedback_parts.append("Table created but columns missing")
    else:
        feedback_parts.append("Table PATIENT_ADMISSIONS missing")

    # 2. Procedure Existence (15)
    if result.get("procedure_exists"):
        if result.get("procedure_status") == "VALID":
            score += 15
            feedback_parts.append("Procedure exists and is VALID")
        else:
            score += 5
            feedback_parts.append("Procedure exists but INVALID")
    else:
        feedback_parts.append("Procedure PARSE_HL7_BATCH not found")

    # 3. Row Count (15)
    # Expected 100 rows (99 random + 1 sentinel)
    count = result.get("row_count", 0)
    if 95 <= count <= 105:
        score += 15
        feedback_parts.append(f"Row count correct ({count})")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Row count mismatch ({count}, expected ~100)")
    else:
        feedback_parts.append("Table is empty")

    # 4. Sentinel Data Checks (60)
    sentinel = result.get("sentinel_data", {})
    if result.get("sentinel_found") and sentinel:
        
        # Name Check (Last, First)
        actual_name = sentinel.get("patient_name", "").strip()
        if actual_name == expected_name:
            score += 15
            feedback_parts.append("Name formatted correctly")
        elif "Everdeen" in actual_name and "Katniss" in actual_name:
            score += 5
            feedback_parts.append(f"Name extracted but formatting wrong ('{actual_name}')")
        else:
            feedback_parts.append(f"Name incorrect ('{actual_name}')")

        # Event Check
        if sentinel.get("message_event") == expected_event:
            score += 10
            feedback_parts.append("Event extracted correctly")
        else:
            feedback_parts.append("Event extraction failed")

        # Diagnosis Check
        if sentinel.get("diagnosis_code") == expected_diag:
            score += 10
            feedback_parts.append("Diagnosis extracted correctly")
        else:
            feedback_parts.append("Diagnosis extraction failed")
            
        # Date Check
        # JSON date often comes as ISO string "2025-11-22T10:30:00"
        admit_date = sentinel.get("admission_date", "")
        if admit_date and "2025-11-22" in admit_date:
            score += 15
            feedback_parts.append("Date parsed correctly")
            # Bonus check for time if possible, but date is main requirement
        else:
            feedback_parts.append(f"Date incorrect ('{admit_date}')")
            
        # MRN Check (Implicitly handled if sentinel found, but check purity)
        if sentinel.get("mrn") == "TEST999":
            score += 10
            feedback_parts.append("MRN extracted correctly")

    else:
        feedback_parts.append("Sentinel record TEST999 not found (Parsing failed)")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }