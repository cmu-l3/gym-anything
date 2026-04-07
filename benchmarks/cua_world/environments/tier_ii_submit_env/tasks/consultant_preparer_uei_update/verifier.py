#!/usr/bin/env python3
"""
Verifier for consultant_preparer_uei_update task.

Scoring (100 pts total, pass threshold: 80):
  20 pts - Export file exists
  30 pts - UEI updated to 'L9KLM2B8N1X5'
  30 pts - Consultant contact added ('Sarah Jenkins', 'EcoCompliance Partners LLC')
  20 pts - Correct contact type ('Tier II Information Contact' or equivalent)
"""

import json
import os
import tempfile

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\consultant_preparer_uei_update_result.json"

def verify_consultant_preparer_uei_update(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 80)
    
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # Do-nothing baseline catch
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output .t2s file not found at C:\\Users\\Docker\\Desktop\\Tier2Output\\apex_final_2024.t2s. Task not completed."
        }

    score = 20
    feedback_parts = ["PASS: Export file exists (+20)"]
    
    # Check creation timing to prevent basic renaming attacks
    if result.get("file_created_during_task", False):
        feedback_parts.append("PASS: File timestamp is valid")
    else:
        feedback_parts.append("WARNING: File modification time is older than task start")

    raw_xml = result.get("raw_xml", "")
    if not raw_xml:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | FAIL: No XML data found in the exported file."
        }

    # 1. Check for UEI
    if "L9KLM2B8N1X5" in raw_xml:
        score += 30
        feedback_parts.append("PASS: UEI 'L9KLM2B8N1X5' found in export (+30)")
    else:
        feedback_parts.append("FAIL: UEI 'L9KLM2B8N1X5' not found in export")

    # 2. Check for Consultant Contact Name and Company
    contact_name_found = "Sarah Jenkins" in raw_xml
    company_found = "EcoCompliance Partners" in raw_xml
    
    if contact_name_found and company_found:
        score += 30
        feedback_parts.append("PASS: Consultant contact 'Sarah Jenkins' / 'EcoCompliance Partners' found (+30)")
    elif contact_name_found or company_found:
        score += 15
        feedback_parts.append("PARTIAL: Consultant name or company found, but not both (+15)")
    else:
        feedback_parts.append("FAIL: Consultant contact 'Sarah Jenkins' / 'EcoCompliance Partners' not found")

    # 3. Check for Contact Type
    if "Tier II Information Contact" in raw_xml or "Regulatory Point of Contact" in raw_xml:
        score += 20
        feedback_parts.append("PASS: Contact type 'Tier II Information Contact' (or equivalent) found (+20)")
    else:
        feedback_parts.append("FAIL: Contact type 'Tier II Information Contact' not found")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }