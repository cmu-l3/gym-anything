#!/usr/bin/env python3
"""
Verifier for stall_margin_assessment@1
"""

import json
import os
import re
import tempfile
import logging
import math

# Logger setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_values(report_text):
    """
    Extracts key numerical values from the report text.
    Returns a dictionary of found values.
    """
    values = {}
    
    # Regex patterns for expected fields
    patterns = {
        "stall_angle": r"Stall Angle.*[:]\s*([0-9\.]+)",
        "cl_max": r"Maximum Cl.*[:]\s*([0-9\.]+)",
        "cl_10": r"Cl at alpha=10.*[:]\s*([0-9\.]+)",
        "cd_10": r"Cd at alpha=10.*[:]\s*([0-9\.]+)",
        "ld_10": r"L/D at alpha=10.*[:]\s*([0-9\.]+)",
        "stall_margin": r"Stall Margin.*[:]\s*([0-9\.]+)",
        "assessment": r"ASSESSMENT.*[:]\s*(SAFE|UNSAFE)"
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, report_text, re.IGNORECASE)
        if match:
            try:
                # Store numbers as floats, text as string
                if key == "assessment":
                    values[key] = match.group(1).upper()
                else:
                    values[key] = float(match.group(1))
            except ValueError:
                pass
                
    return values

def verify_stall_margin_assessment(traj, env_info, task_info):
    """
    Verifies the stall margin assessment task.
    
    Criteria:
    1. Report file exists and was created during task. (10 pts)
    2. Project file exists and was created during task. (10 pts)
    3. Report formatting allows parsing of values. (10 pts)
    4. Values are within physically realistic ranges for NACA 4412 @ Re=1e6. (40 pts)
    5. Internal consistency (Margin = Stall - 10, L/D = Cl/Cd). (20 pts)
    6. Correct assessment (Safe/Unsafe) based on margin. (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})

    score = 0
    feedback_parts = []
    
    # --- Step 1: Load Result JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- Step 2: Verify Files Existence & Timing ---
    if result_data.get('report_created_during_task'):
        score += 10
        feedback_parts.append("Report file created during task.")
    elif result_data.get('report_exists'):
        score += 5
        feedback_parts.append("Report file exists but timestamp check failed.")
    else:
        feedback_parts.append("Report file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if result_data.get('project_created_during_task') and result_data.get('project_size', 0) > 1000:
        score += 10
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file missing or too small.")

    # --- Step 3: Parse Report Content ---
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    report_content = ""
    try:
        copy_from_env(result_data.get('report_path'), temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Could not read report content: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
            
    values = parse_report_values(report_content)
    
    required_keys = ["stall_angle", "cl_max", "cl_10", "cd_10", "stall_margin"]
    missing_keys = [k for k in required_keys if k not in values]
    
    if not missing_keys:
        score += 10
        feedback_parts.append("Report format correct.")
    else:
        feedback_parts.append(f"Report missing values: {missing_keys}")
        
    # --- Step 4: Validate Physical Accuracy (40 pts) ---
    # Valid ranges defined in metadata/ground_truth
    
    # Stall Angle
    sa = values.get("stall_angle", 0)
    if gt.get("stall_angle_min") <= sa <= gt.get("stall_angle_max"):
        score += 10
    else:
        feedback_parts.append(f"Stall angle {sa} out of range ({gt.get('stall_angle_min')}-{gt.get('stall_angle_max')})")

    # Cl Max
    cl_max = values.get("cl_max", 0)
    if gt.get("cl_max_min") <= cl_max <= gt.get("cl_max_max"):
        score += 10
    else:
        feedback_parts.append(f"Cl_max {cl_max} out of range")

    # Cl at 10 deg
    cl_10 = values.get("cl_10", 0)
    if gt.get("cl_10_min") <= cl_10 <= gt.get("cl_10_max"):
        score += 10
    else:
        feedback_parts.append(f"Cl@10 {cl_10} out of range")

    # Cd at 10 deg
    cd_10 = values.get("cd_10", 0)
    if gt.get("cd_10_min") <= cd_10 <= gt.get("cd_10_max"):
        score += 10
    else:
        feedback_parts.append(f"Cd@10 {cd_10} out of range")

    # --- Step 5: Internal Consistency (20 pts) ---
    consistency_passed = True
    
    # Margin check
    margin = values.get("stall_margin", -999)
    calc_margin = sa - 10.0
    if abs(margin - calc_margin) < 0.5:
        score += 10
    else:
        feedback_parts.append(f"Stall Margin inconsistent: Reported {margin} vs Calc {calc_margin}")
        consistency_passed = False

    # L/D check
    ld = values.get("ld_10", 0)
    if cd_10 > 0:
        calc_ld = cl_10 / cd_10
        # Allow 5% tolerance
        if abs(ld - calc_ld) / calc_ld < 0.05:
            score += 10
        else:
            feedback_parts.append(f"L/D inconsistent: Reported {ld} vs Calc {calc_ld:.2f}")
            consistency_passed = False
    else:
        feedback_parts.append("Cannot verify L/D (Cd is 0 or missing)")
        consistency_passed = False

    # --- Step 6: Assessment Logic (10 pts) ---
    assessment = values.get("assessment", "UNKNOWN")
    is_safe = margin > gt.get("margin_threshold", 3.0)
    
    if (is_safe and assessment == "SAFE") or (not is_safe and assessment == "UNSAFE"):
        score += 10
    else:
        feedback_parts.append(f"Assessment '{assessment}' inconsistent with margin {margin}")

    # --- VLM Verification (Bonus/Confirmation) ---
    # We can perform a lightweight VLM check here if needed, 
    # but the numerical verification is quite robust for this task.
    # If score is high but files look suspicious, VLM could flag it.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }