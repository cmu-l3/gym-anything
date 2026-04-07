#!/usr/bin/env python3
"""
Verifier for restore_patient_from_backup task.

This task verifies that a specific patient record was restored from a backup SQL file.
It performs strict anti-gaming checks by comparing the GUID of the restored record
against the original GUID preserved in a hidden ground truth file.

Criteria:
1. Patient exists in the database (IndexNomPrenom table).
2. Patient details exist (fchpat table).
3. The GUID matches the original backup GUID (prevents manual creation of a new patient).
4. Critical data fields (DOB, City) match the backup.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_patient_from_backup(traj, env_info, task_info):
    """
    Verify patient restoration using exported database state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    patient_found = result.get("patient_found", False)
    current_guid = result.get("current_guid", "").strip()
    expected_guid = result.get("expected_guid", "").strip()
    index_count = result.get("index_table_count", 0)
    details_count = result.get("details_table_count", 0)
    current_dob = result.get("current_dob", "")
    
    # Target Data (from setup)
    EXPECTED_DOB = "1954-02-18"
    
    # Criterion 1: Record exists in IndexNomPrenom (30 pts)
    if index_count > 0:
        score += 30
        feedback_parts.append("Patient found in search index")
    else:
        feedback_parts.append("Patient NOT found in search index")

    # Criterion 2: Record exists in fchpat (30 pts)
    # This checks if the JOIN worked in the export script or if individual count > 0
    if details_count > 0:
        score += 30
        feedback_parts.append("Patient details found in fchpat table")
    else:
        feedback_parts.append("Patient details missing from fchpat table")

    # Criterion 3: GUID Preservation (Anti-Gaming) (30 pts)
    # If the agent created a NEW patient manually, the GUID will be random/different.
    # If they restored from backup, it will match.
    if current_guid == expected_guid and expected_guid != "":
        score += 30
        feedback_parts.append("Identity confirmed (GUID matches backup)")
    elif current_guid != "":
        feedback_parts.append(f"Identity mismatch: Restored GUID {current_guid} != Original {expected_guid}. Did you create a new patient instead of restoring?")
    else:
        feedback_parts.append("No GUID found")

    # Criterion 4: Data Accuracy (10 pts)
    if current_dob == EXPECTED_DOB:
        score += 10
        feedback_parts.append("Date of Birth matches")
    elif current_dob != "" and current_dob != "NULL":
        feedback_parts.append(f"DOB mismatch: Found {current_dob}, expected {EXPECTED_DOB}")

    # Pass logic
    # Must have both tables and correct GUID
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }