#!/usr/bin/env python3
"""
Verifier for Bayesian RM ANOVA Task (JASP)
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_rm_anova_bigfive(traj, env_info, task_info):
    """
    Verifies the Bayesian Repeated Measures ANOVA task.
    
    Criteria:
    1. JASP project file created/saved (20 pts)
    2. Report file created (10 pts)
    3. Bayes Factor reported indicates strong evidence (35 pts)
    4. Correct highest scoring item identified (35 pts)
    """
    
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. Verify JASP File (20 pts)
    jasp_info = result.get("jasp_file", {})
    if jasp_info.get("exists") and jasp_info.get("created_during_task"):
        if jasp_info.get("size_bytes", 0) > 1000: # Empty file check
            score += 20
            feedback.append("JASP project file saved.")
        else:
            score += 5
            feedback.append("JASP file exists but seems empty.")
    else:
        feedback.append("JASP project file not saved or not modified.")
        
    # 2. Verify Report Existence (10 pts)
    report_info = result.get("report_file", {})
    content = report_info.get("content", "")
    
    if report_info.get("exists") and report_info.get("created_during_task") and len(content.strip()) > 0:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or empty.")
        
    # 3. Verify BF10 Value (35 pts)
    # Ground truth: For Big Five items, differences are usually huge, so BF10 should be very large.
    # We look for "BF10: <value>"
    bf_match = re.search(r"BF10:\s*([0-9\.eE\+]+|inf|infinity)", content, re.IGNORECASE)
    
    if bf_match:
        val_str = bf_match.group(1).lower()
        try:
            if "inf" in val_str:
                val = float('inf')
            else:
                val = float(val_str)
            
            # Threshold: > 1000 (Extreme evidence)
            if val > 1000:
                score += 35
                feedback.append(f"Bayes Factor reported correctly (Strong/Extreme evidence: {val_str}).")
            else:
                score += 10
                feedback.append(f"Bayes Factor reported ({val}), but expected value > 1000.")
        except ValueError:
            feedback.append(f"Could not parse Bayes Factor value: {val_str}")
    else:
        feedback.append("Bayes Factor not found in report (Expected format 'BF10: value').")

    # 4. Verify Highest Item (35 pts)
    # Compare against ground truth calculated in export script
    gt = result.get("ground_truth", {})
    highest_item_gt = gt.get("highest_item", "").strip().upper()
    
    if gt.get("status") == "success" and highest_item_gt:
        item_match = re.search(r"Highest Item:\s*(E[1-5])", content, re.IGNORECASE)
        if item_match:
            reported_item = item_match.group(1).upper()
            if reported_item == highest_item_gt:
                score += 35
                feedback.append(f"Correctly identified highest scoring item: {reported_item}.")
            else:
                feedback.append(f"Incorrect highest item reported. Reported: {reported_item}, Actual: {highest_item_gt}.")
        else:
            feedback.append("Highest Item not found in report (Expected format 'Highest Item: E#').")
    else:
        # Fallback if ground truth calc failed (shouldn't happen)
        feedback.append("Could not verify highest item (internal calculation error).")
        # Give partial points if it looks like a valid item
        if re.search(r"Highest Item:\s*E[1-5]", content, re.IGNORECASE):
            score += 15
            feedback.append("Item reported, but ground truth verification failed.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }