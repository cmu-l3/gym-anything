#!/usr/bin/env python3
"""
Verifier for PL/SQL Debug Challenge.
Scores the agent based on 5 independent bug fixes and compilation status.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plsql_debug_challenge(traj, env_info, task_info):
    """
    Verify the PL/SQL debugging task results.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            copy_from_env("/tmp/plsql_debug_result.json", tmp.name)
            tmp_name = tmp.name
        
        with open(tmp_name, "r") as f:
            result = json.load(f)
        os.unlink(tmp_name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}

    score = 0
    max_score = 100
    feedback = []
    
    # 1. Check Compilation Status (5 pts)
    # All 5 objects should be VALID
    comp_status = result.get("compilation_status", {})
    valid_count = sum(1 for status in comp_status.values() if status == "VALID")
    if valid_count == 5:
        score += 5
        feedback.append("All objects compiled successfully (+5)")
    else:
        feedback.append(f"Only {valid_count}/5 objects are VALID compilation")

    # 2. Bug 1: CALC_ANNUAL_COMPENSATION (16 pts)
    # Null comm check (8 pts)
    if result.get("bug1_calc_comp_null", {}).get("passed"):
        score += 8
        feedback.append("Fixed NULL commission handling (+8)")
    else:
        val = result.get("bug1_calc_comp_null", {}).get("val")
        feedback.append(f"NULL commission test failed (Got: {val})")

    # Valid comm check (8 pts)
    if result.get("bug1_calc_comp_valid", {}).get("passed"):
        score += 8
        feedback.append("Valid commission calculation correct (+8)")
    else:
        feedback.append("Valid commission test failed")

    # 3. Bug 2: BUILD_DEPT_SALARY_RANKINGS (16 pts)
    # Check if Rank 1 is assigned to highest salary
    if result.get("bug2_ranking_check", {}).get("passed"):
        score += 16
        feedback.append("Fixed salary ranking sort order (+16)")
    else:
        rank = result.get("bug2_ranking_check", {}).get("rank")
        feedback.append(f"Ranking test failed (ID 100 Rank: {rank}, Expected: 1)")

    # 4. Bug 3: FIND_DEPT_TOP_EARNER (16 pts)
    if result.get("bug3_top_earner", {}).get("passed"):
        score += 16
        feedback.append("Fixed top earner logic (MIN->MAX) (+16)")
    else:
        val = result.get("bug3_top_earner", {}).get("id")
        feedback.append(f"Top earner test failed (Got ID: {val})")

    # 5. Bug 4: GET_SALARY_PERCENTILE (16 pts)
    if result.get("bug4_percentile", {}).get("passed"):
        score += 16
        feedback.append("Fixed departmental percentile scope (+16)")
    else:
        val = result.get("bug4_percentile", {}).get("val")
        feedback.append(f"Percentile test failed (Got: {val})")

    # 6. Bug 5: ADJUST_SALARY (16 pts)
    if result.get("bug5_adjust_salary", {}).get("passed"):
        score += 16
        feedback.append("Fixed salary adjustment formula (+16)")
    else:
        new_val = result.get("bug5_adjust_salary", {}).get("new")
        feedback.append(f"Salary adjust test failed (Got: {new_val}, Expected: 5500)")

    # 7. Bug Report File (15 pts)
    if result.get("bug_report_exists") and result.get("bug_report_size", 0) > 100:
        score += 15
        feedback.append("Bug report created (+15)")
    elif result.get("bug_report_exists"):
        score += 5
        feedback.append("Bug report empty or too small (+5)")
    else:
        feedback.append("Bug report not found")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }