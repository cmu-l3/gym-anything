#!/usr/bin/env python3
"""
Verifier for Incumbency RDD Task.

Verifies:
1. Installation of required package (inferred from successful execution)
2. Creation of valid McCrary density plot
3. Creation of RDD visualization plot
4. Accurate estimation of LATE (Local Average Treatment Effect)
5. Anti-gaming checks (timestamps, file modification)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_incumbency_rdd(traj, env_info, task_info):
    """
    Verify the RDD analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    # Load result JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: Script Modification (10 pts) ---
    if result.get("script_modified", False):
        score += 10
        feedback_parts.append("Script modified (+10)")
        
        # Simple check if 'rdd' package is mentioned in snippet
        content = result.get("script_content_snippet", "").lower()
        if "library(rdd)" in content or "require(rdd)" in content or "rdd::" in content:
            feedback_parts.append("Package 'rdd' loaded")
        else:
            feedback_parts.append("Warning: 'rdd' package usage not explicitly seen in snippet")
    else:
        feedback_parts.append("Script not modified (0/10)")

    # --- CRITERION 2: McCrary Test Plot (20 pts) ---
    if result.get("mccrary_exists", False):
        if result.get("mccrary_new", False):
            if result.get("mccrary_size", 0) > 5000: # Minimal size check for a real plot
                score += 20
                feedback_parts.append("McCrary plot created successfully (+20)")
            else:
                score += 10
                feedback_parts.append("McCrary plot file exists but is suspiciously small (+10)")
        else:
            feedback_parts.append("McCrary plot file predates task start (0/20)")
    else:
        feedback_parts.append("McCrary plot missing (0/20)")

    # --- CRITERION 3: RDD Visualization Plot (20 pts) ---
    if result.get("rdd_plot_exists", False):
        if result.get("rdd_plot_new", False):
            if result.get("rdd_plot_size", 0) > 5000:
                score += 20
                feedback_parts.append("RDD visualization created successfully (+20)")
            else:
                score += 10
                feedback_parts.append("RDD plot file exists but is suspiciously small (+10)")
        else:
            feedback_parts.append("RDD plot file predates task start (0/20)")
    else:
        feedback_parts.append("RDD visualization missing (0/20)")

    # --- CRITERION 4: CSV Existence (10 pts) ---
    if result.get("csv_exists", False) and result.get("csv_new", False):
        score += 10
        feedback_parts.append("Results CSV created (+10)")
    else:
        feedback_parts.append("Results CSV missing or old (0/10)")

    # --- CRITERION 5: Statistical Accuracy (40 pts) ---
    # The Lee (2008) LATE is typically around 0.08 (8 percentage points)
    late_val = result.get("late_value")
    
    if late_val is not None:
        # Check range [0.05, 0.12]
        if 0.05 <= late_val <= 0.12:
            score += 40
            feedback_parts.append(f"LATE estimate ({late_val:.4f}) is accurate (+40)")
        else:
            # Partial credit if they calculated SOMETHING but it's off
            score += 10
            feedback_parts.append(f"LATE estimate ({late_val:.4f}) is outside expected range [0.05, 0.12] (+10)")
    else:
        feedback_parts.append("LATE value not found in CSV (0/40)")

    # --- Final Evaluation ---
    passed = (score >= 70) and (late_val is not None and 0.05 <= late_val <= 0.12)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }