#!/usr/bin/env python3
"""
Verifier for anti_forensics_double_recovery task.

Scoring (100 pts total, pass threshold = 70):
  25 pts  — Partition table recovered (mmls success on raw image file)
  15 pts  — Autopsy case created and DB found
  20 pts  — File system successfully parsed and deleted file indexed
  15 pts  — Deleted file tagged as 'Notable Item'
  25 pts  — Report contains correct extracted Informant ID
"""

import json
import os
import tempfile

def verify_anti_forensics_double_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - framework error"}

    meta = task_info.get("metadata", {})
    expected_id = meta.get("informant_id", "X-992-ALPHA")
    
    # Extract JSON results from environment
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task was not attempted or export did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Partition recovered
    if result.get("partition_recovered"):
        score += 25
        feedback_parts.append("PASS Partition table recovered (+25)")
    else:
        feedback_parts.append("FAIL Partition table not recovered")
        
    # 2. Case DB created
    if result.get("case_db_found"):
        score += 15
        feedback_parts.append("PASS Case DB found (+15)")
    else:
        feedback_parts.append("FAIL Case DB not found")
        
    # 3. File parsed
    if result.get("file_found_in_db"):
        score += 20
        feedback_parts.append("PASS File system parsed and deleted file found (+20)")
    else:
        feedback_parts.append("FAIL Deleted file not found in DB")
        
    # 4. Tagged
    if result.get("file_tagged"):
        score += 15
        feedback_parts.append("PASS File tagged as Notable Item (+15)")
    else:
        feedback_parts.append("FAIL File not tagged as Notable Item")
        
    # 5. Report content
    report_content = result.get("report_content", "")
    if result.get("report_exists"):
        has_id = expected_id in report_content
        has_case = "INV-REC-099" in report_content
        
        if has_id and has_case:
            score += 25
            feedback_parts.append("PASS Report contains correct Informant ID and format (+25)")
        elif has_id:
            score += 15
            feedback_parts.append("PARTIAL Report contains ID but missing format elements (+15)")
        else:
            feedback_parts.append("FAIL Report exists but lacks correct Informant ID")
    else:
        feedback_parts.append("FAIL Report not found")

    passed = score >= 70 and result.get("partition_recovered") and (expected_id in report_content)
    
    if result.get("error"):
        feedback_parts.append(f"ERRORS: {result['error']}")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }