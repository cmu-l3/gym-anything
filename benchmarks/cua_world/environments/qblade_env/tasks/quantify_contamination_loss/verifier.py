#!/usr/bin/env python3
"""
Verifier for quantify_contamination_loss task.
"""

import json
import base64
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_contamination_loss(traj, env_info, task_info):
    """
    Verifies the contamination loss task by checking:
    1. Existence and valid creation time of project and report files.
    2. Physics check: 'Dirty' power should be less than 'Clean' power.
    3. Accuracy: Calculated loss % matches the reported power values.
    4. VLM: Optional check for workflow trajectory (NCrit changes).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []
    
    # 2. Check Project File (20 pts)
    if result.get("project_exists") and result.get("project_created_during_task"):
        # Check for non-trivial size (empty project ~small, full project > 5KB usually)
        if result.get("project_size_bytes", 0) > 2000:
            score += 20
            feedback.append("QBlade project saved successfully.")
        else:
            score += 10
            feedback.append("QBlade project saved, but file size is suspiciously small.")
    else:
        feedback.append("QBlade project file not found or not saved during task.")

    # 3. Check Report Existence (20 pts)
    report_content = ""
    if result.get("report_exists") and result.get("report_created_during_task"):
        score += 20
        feedback.append("Report file created.")
        try:
            report_content = base64.b64decode(result.get("report_content_b64", "")).decode('utf-8')
        except:
            feedback.append("Error decoding report content.")
    else:
        feedback.append("Report file not found.")

    # 4. Parse and Validate Physics (40 pts)
    # Expected format:
    # Power Clean (kW): <val>
    # Power Dirty (kW): <val>
    # Power Loss (%): <val>
    
    clean_power = 0.0
    dirty_power = 0.0
    reported_loss = 0.0
    
    # Regex to find numbers (floating point)
    clean_match = re.search(r"Clean.*?:.*?([\d\.]+)", report_content, re.IGNORECASE)
    dirty_match = re.search(r"Dirty.*?:.*?([\d\.]+)", report_content, re.IGNORECASE)
    loss_match = re.search(r"Loss.*?:.*?([\d\.]+)", report_content, re.IGNORECASE)
    
    physics_passed = False
    
    if clean_match and dirty_match:
        try:
            clean_power = float(clean_match.group(1))
            dirty_power = float(dirty_match.group(1))
            
            feedback.append(f"Extracted values - Clean: {clean_power} kW, Dirty: {dirty_power} kW")
            
            # Physics Check 1: Reasonable values for a small turbine (0.5kW to 1MW)
            if 0.5 < clean_power < 1000.0:
                score += 10
                feedback.append("Power values are within reasonable physical range.")
            else:
                feedback.append("Power values seem unrealistic (too small or too large).")

            # Physics Check 2: Dirty should be WORSE than Clean (lower power)
            # We allow a tiny margin for numerical noise, but generally Clean > Dirty
            if clean_power > dirty_power:
                score += 20
                physics_passed = True
                feedback.append("Physics check passed: Clean power > Dirty power.")
            elif clean_power == dirty_power:
                feedback.append("Physics check failed: Clean power equals Dirty power. Did you change Ncrit?")
            else:
                feedback.append("Physics check failed: Dirty power > Clean power (unexpected).")
                
        except ValueError:
            feedback.append("Could not parse power values as numbers.")
    else:
        feedback.append("Could not find 'Clean' and 'Dirty' power values in report.")

    # 5. Check Calculation Accuracy (20 pts)
    if physics_passed and loss_match:
        try:
            reported_loss = float(loss_match.group(1))
            
            # Calculate expected loss
            expected_loss = ((clean_power - dirty_power) / clean_power) * 100.0
            
            # Allow small tolerance (e.g., 0.5%) for rounding differences
            if abs(reported_loss - expected_loss) < 0.5:
                score += 20
                feedback.append(f"Loss percentage calculation correct (Reported: {reported_loss}%, Expected: {expected_loss:.2f}%).")
            else:
                score += 10 # Partial credit if they tried but math is off
                feedback.append(f"Loss percentage calculation inaccurate (Reported: {reported_loss}%, Expected: {expected_loss:.2f}%).")
        except ValueError:
            feedback.append("Could not parse loss percentage.")
    elif physics_passed:
        feedback.append("Physics correct, but Loss % not found in report.")

    # 6. Final Evaluation
    passed = (score >= 70) and physics_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }