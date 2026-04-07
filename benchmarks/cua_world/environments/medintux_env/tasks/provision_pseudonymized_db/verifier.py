#!/usr/bin/env python3
"""
Verifier for provision_pseudonymized_db task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_pseudonymized_db(traj, env_info, task_info):
    """
    Verify the database provisioning and pseudonymization task.
    
    Criteria:
    1. Database Created (10 pts)
    2. Tables Cloned & Row Counts Match (20 pts)
    3. Names Masked Correctly (20 pts)
    4. Contact Info Masked Correctly (15 pts)
    5. Demographics Preserved (20 pts)
    6. Source Integrity (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Exists (10 pts)
    if result.get("db_exists", False):
        score += 10
        feedback_parts.append("Target database created.")
    else:
        feedback_parts.append("Target database NOT found.")
        return {"passed": False, "score": 0, "feedback": "Target database not created."}

    # 2. Tables & Rows (20 pts)
    if result.get("tables_exist", False):
        if result.get("row_count_match", False):
            score += 20
            feedback_parts.append("Tables cloned with correct row counts.")
        else:
            score += 10
            feedback_parts.append("Tables created but row counts do not match source.")
    else:
        feedback_parts.append("Required tables missing in target DB.")

    # 3 & 4. Masking (35 pts total split in script, here simplified based on result flag)
    # The export script aggregates masking checks. We'll split points if partial?
    # Actually, export script provides `masking_correct` boolean.
    metrics = result.get("metrics", {})
    mask_fail_idx = metrics.get("mask_failures_index", 999)
    mask_fail_pat = metrics.get("mask_failures_pat", 999)
    
    if mask_fail_idx == 0:
        score += 20
        feedback_parts.append("Names successfully masked.")
    else:
        feedback_parts.append(f"Name masking failed ({mask_fail_idx} rows revealed).")

    if mask_fail_pat == 0:
        score += 15
        feedback_parts.append("Contact info successfully masked.")
    else:
        feedback_parts.append(f"Contact info masking failed ({mask_fail_pat} rows revealed).")

    # 5. Preservation (20 pts)
    if result.get("data_preserved", False):
        score += 20
        feedback_parts.append("Demographic data preserved correctly.")
    else:
        fail_count = metrics.get("preservation_failures", "unknown")
        feedback_parts.append(f"Demographic data corrupted/changed ({fail_count} rows mismatch).")

    # 6. Source Integrity (15 pts)
    if result.get("source_integrity", False):
        score += 15
        feedback_parts.append("Source database untouched.")
    else:
        feedback_parts.append("WARNING: Source database was modified!")

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }