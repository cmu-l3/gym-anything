#!/usr/bin/env python3
"""Verifier for debug_infinite_loop_dose task."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_infinite_loop_dose(traj, env_info, task_info):
    """
    Verify that the infinite loop was fixed and the batch process completed.
    
    Criteria:
    1. Output file (dose_report.csv) exists and contains "Patient_003" (40 pts)
       - Proves the loop was broken and execution continued.
    2. Output file created AFTER task start (10 pts)
       - Anti-gaming check.
    3. Source code contains a fix mechanism (30 pts)
       - Look for 'break', 'maxIterations', 'count', or loop condition changes.
    4. VLM/Trace verification (20 pts)
       - Verify debugging or code editing happened.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    output_exists = result.get('output_exists', False)
    output_timestamp = result.get('output_timestamp', 0)
    output_content = result.get('output_content', "")
    src_content = result.get('src_content', "")
    
    # --- Criterion 1 & 2: Output Verification (50 pts total) ---
    if output_exists:
        # Check timestamp
        if output_timestamp > task_start:
            score += 10
            feedback_parts.append("Output file created during task")
        else:
            feedback_parts.append("Output file is old/stale")

        # Check content for Patient_003
        if "Patient_003" in output_content and "SUCCESS" in output_content:
            score += 40
            feedback_parts.append("Batch processing completed successfully (Patient_003 found)")
        elif "Patient_003" in output_content:
            score += 20
            feedback_parts.append("Batch processing ran but Patient_003 status unclear")
        else:
            feedback_parts.append("Output file exists but missing Patient_003 data")
    else:
        feedback_parts.append("dose_report.csv not found")

    # --- Criterion 3: Source Code Analysis (30 pts) ---
    # We look for typical patterns used to break infinite loops
    fix_detected = False
    
    # Check for loop counter logic
    if re.search(r'(int|long)\s+\w+\s*=\s*0', src_content) and \
       re.search(r'\+\+', src_content) and \
       (re.search(r'if\s*\(.*>\s*\d+\)', src_content) or re.search(r'while\s*\(.*<\s*\d+', src_content)):
        fix_detected = True
        feedback_parts.append("Detected iteration counter logic")
        
    # Check for simple break condition inside loop
    elif "break;" in src_content:
        # Need to be careful this isn't a false positive, but in the provided template there were no breaks.
        fix_detected = True
        feedback_parts.append("Detected 'break' statement")
        
    # Check for System.currentTimeMillis check (timeout logic)
    elif "System.currentTimeMillis" in src_content and "if" in src_content and ">" in src_content:
        fix_detected = True
        feedback_parts.append("Detected timeout logic")

    if fix_detected:
        score += 30
    else:
        # Fallback: if output is correct, maybe they did something clever we missed
        if score >= 40: 
            score += 10 # Give partial credit if it works but we can't parse the fix
            feedback_parts.append("Code fix not explicitly recognized, but output is correct")
        else:
            feedback_parts.append("No loop termination logic detected in source code")

    # --- Criterion 4: VLM Verification (20 pts) ---
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Debug an infinite loop in Eclipse IDE",
            checklist_items=[
                "Eclipse IDE is open",
                "The 'RayPlan' project is loaded",
                "The Debug perspective or Debug view was used",
                "GradientDescentOptimizer.java was edited",
                "Console shows 'Batch processing complete'"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            score += 20
            feedback_parts.append("VLM confirmed debugging workflow")
        else:
            feedback_parts.append("VLM did not verify debugging workflow")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # If VLM fails but file output is perfect, give benefit of doubt
        if score >= 80:
            score += 20
            feedback_parts.append("VLM skipped, assume pass due to perfect output")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }