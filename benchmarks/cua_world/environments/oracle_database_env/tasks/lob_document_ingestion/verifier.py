#!/usr/bin/env python3
"""
Verifier for LOB Document Ingestion task.

Verifies:
1. Oracle Directory 'LICENSE_DIR' exists and points to /tmp/licenses.
2. Table 'LICENSE_ARCHIVE' exists with BLOB and HASH columns.
3. 5 files were ingested into the BLOB column.
4. SHA-256 hashes were correctly computed and stored.
5. Duplicate report identifies 'vendor_terms.txt' and 'apache-2.0.txt'.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lob_ingestion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    
    # 1. Directory Object (10 pts)
    if result.get("directory_created"):
        if result.get("directory_path_correct"):
            score += 10
            feedback_parts.append("Directory object correct")
        else:
            score += 5
            feedback_parts.append("Directory created but wrong path")
    else:
        feedback_parts.append("Directory LICENSE_DIR not found")

    # 2. Table Structure (10 pts)
    if result.get("table_exists"):
        if result.get("columns_correct"):
            score += 10
            feedback_parts.append("Table structure correct")
        else:
            score += 5
            feedback_parts.append("Table exists but columns mismatch")
    else:
        feedback_parts.append("Table LICENSE_ARCHIVE not found")

    # 3. Data Ingestion (25 pts)
    row_count = result.get("row_count", 0)
    if row_count == 5:
        score += 25
        feedback_parts.append("All 5 files ingested")
    elif row_count > 0:
        partial = row_count * 5
        score += partial
        feedback_parts.append(f"{row_count}/5 files ingested")
    else:
        feedback_parts.append("No rows in table")

    # 4. BLOB Content (15 pts)
    # If rows exist but BLOBs are empty, this fails
    if result.get("blob_content_valid"):
        score += 15
        feedback_parts.append("BLOB content valid")
    elif row_count > 0:
        feedback_parts.append("Rows exist but BLOBs empty or invalid")

    # 5. Hash Computation (25 pts)
    if result.get("hashes_correct"):
        score += 25
        feedback_parts.append("Hashes computed correctly")
    elif result.get("hashes_populated"):
        score += 10
        feedback_parts.append("Hashes populated but incorrect values")
    else:
        feedback_parts.append("Hashes missing")

    # 6. Duplicate Identification (15 pts)
    # Check report content
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "").lower()
    
    dup_found_in_report = False
    if report_exists:
        if "vendor_terms.txt" in report_content and "apache-2.0.txt" in report_content:
            dup_found_in_report = True
    
    if dup_found_in_report:
        score += 15
        feedback_parts.append("Duplicate report correct")
    elif report_exists:
        score += 5
        feedback_parts.append("Report exists but missing duplicate info")
    else:
        feedback_parts.append("Duplicate report missing")

    # Pass logic
    passed = score >= 60 and row_count >= 5 and result.get("hashes_populated")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }