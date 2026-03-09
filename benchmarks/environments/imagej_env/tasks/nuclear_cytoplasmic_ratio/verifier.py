#!/usr/bin/env python3
"""
Verifier for Nuclear-to-Cytoplasmic Ratio task.

Criteria:
1. Result file exists and was created during the task. (15 pts)
2. Contains data for at least 3 cells (3 rows of data). (20 pts)
3. Columns/Data present for Nuclear intensity. (15 pts)
4. Columns/Data present for Cytoplasmic intensity. (15 pts)
5. Columns/Data present for Ratio. (20 pts)
6. Mathematical consistency check (Ratio ~ Nuclear/Cytoplasmic). (15 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nuclear_cytoplasmic_ratio(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
    
    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/nuclear_cytoplasmic_ratio_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timestamp (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("Result file created successfully")
    elif result.get("file_exists"):
        feedback_parts.append("FAIL: Result file exists but is old (pre-dated task)")
    else:
        feedback_parts.append("FAIL: Result file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Row Count (>= 3 cells) (20 pts)
    rows = result.get("row_count", 0)
    if rows >= 3:
        score += 20
        feedback_parts.append(f"Measured {rows} cells (Target: >=3)")
    else:
        feedback_parts.append(f"FAIL: Only {rows} cells measured (Target: >=3)")

    # 3. Nuclear Data (15 pts)
    if result.get("has_nuclear_data"):
        score += 15
        feedback_parts.append("Nuclear data found")
    else:
        feedback_parts.append("FAIL: Nuclear data column missing")

    # 4. Cytoplasmic Data (15 pts)
    if result.get("has_cytoplasmic_data"):
        score += 15
        feedback_parts.append("Cytoplasmic data found")
    else:
        feedback_parts.append("FAIL: Cytoplasmic data column missing")
        
    # 5. Ratio Data (20 pts)
    if result.get("has_ratio_data"):
        score += 20
        feedback_parts.append("Ratio data found")
    else:
        feedback_parts.append("FAIL: Ratio column missing")

    # 6. Consistency Check (15 pts)
    # Checks if Ratio column values approx equal Nuclear / Cytoplasmic
    if result.get("consistent_ratios"):
        score += 15
        feedback_parts.append("Ratio calculations verified consistent")
    elif result.get("has_ratio_data"):
        feedback_parts.append("WARN: Ratio values do not match N/C calculation (math error?)")
        
    # Final Pass/Fail
    passed = (score >= 60) and (rows >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }