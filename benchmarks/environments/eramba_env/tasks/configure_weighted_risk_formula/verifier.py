#!/usr/bin/env python3
"""
Verifier for configure_weighted_risk_formula task.

Verifies that the agent successfully updated the Risk Calculation formula
in the Eramba database to a weighted addition model.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_weighted_risk_formula(traj, env_info, task_info):
    """
    Verify the risk calculation formula update.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    final_formula = result.get("final_formula", "").lower().replace(" ", "")  # Normalize for comparison
    initial_formula = result.get("initial_formula", "").lower().replace(" ", "")
    modified_ts_str = result.get("modified_timestamp", "")
    task_start = result.get("task_start", 0)
    
    score = 0
    feedback_parts = []

    # 3. Scoring Criteria

    # Criterion A: Formula Changed (10 pts)
    # Anti-gaming: Did it actually change from start?
    if final_formula != initial_formula and final_formula != "":
        score += 10
        feedback_parts.append("Formula was modified.")
    elif final_formula == "":
        feedback_parts.append("Formula is empty.")
    else:
        feedback_parts.append("Formula was not changed from initial state.")

    # Criterion B: Contains Key Variables (30 pts)
    # Must contain 'likelihood' and 'impact'
    if "likelihood" in final_formula and "impact" in final_formula:
        score += 30
        feedback_parts.append("Formula contains required variables (Likelihood, Impact).")
    else:
        feedback_parts.append("Formula missing 'likelihood' or 'impact' variables.")

    # Criterion C: Contains Weighted Logic (40 pts)
    # Looking for structure roughly equivalent to: likelihood + (2 * impact)
    # Normalized string check: "likelihood+(2*impact)" or "likelihood+2*impact"
    
    has_plus = "+" in final_formula
    has_multi = "*" in final_formula
    has_weight = "2" in final_formula
    
    if has_plus and has_multi and has_weight:
        # Check specific structure: 2*impact
        if "2*impact" in final_formula or "impact*2" in final_formula:
            score += 40
            feedback_parts.append("Formula implements weighted logic correctly (2 * Impact).")
        else:
            score += 20
            feedback_parts.append("Formula contains +, *, and 2, but structure seems incorrect (expected 2*impact).")
    else:
        feedback_parts.append("Formula missing mathematical operators (+, *) or weight (2).")

    # Criterion D: Modification Timestamp (20 pts)
    # Anti-gaming: Ensure DB was updated *after* task start
    # Format typically "YYYY-MM-DD HH:MM:SS" from MySQL
    valid_timestamp = False
    try:
        if modified_ts_str and modified_ts_str != "NULL":
            mod_dt = datetime.strptime(modified_ts_str, "%Y-%m-%d %H:%M:%S")
            mod_ts = mod_dt.timestamp()
            # Allow small clock skew (e.g. 60s) but generally mod_ts > task_start
            if mod_ts >= (task_start - 5): 
                valid_timestamp = True
    except Exception as e:
        logger.warning(f"Timestamp parsing failed: {e}")
        # Fallback: if formula changed from initial, we assume it happened now since we controlled the env
        if final_formula != initial_formula:
            valid_timestamp = True

    if valid_timestamp:
        score += 20
        feedback_parts.append("Database record updated during task window.")
    else:
        feedback_parts.append("Database modification timestamp validation failed.")

    # 4. Final Verdict
    # Strict pass: Must have correct variables and weighted logic
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": {
            "final_formula_raw": result.get("final_formula", ""),
            "normalized": final_formula
        }
    }