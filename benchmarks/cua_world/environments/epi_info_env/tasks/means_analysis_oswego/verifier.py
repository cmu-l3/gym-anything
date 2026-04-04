#!/usr/bin/env python3
"""
Verifier for Epi Info 7 Means Analysis Task.

Criteria:
1. Analysis module open (Anti-gaming check)
2. HTML output file exists, is valid size, and created during task.
3. Summary text file exists and contains statistical values matching the Oswego dataset.
   - Mean Age (Ill=Yes): ~36.3
   - Mean Age (Ill=No): ~33.9
   - P-value: ~0.54
4. VLM verification of trajectory (optional but recommended for visual confirmation).
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_means_analysis_oswego(traj, env_info, task_info):
    """
    Verify the Means Analysis task on Oswego data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_mean_yes = metadata.get('expected_mean_yes', 36.3)
    expected_mean_no = metadata.get('expected_mean_no', 33.9)
    expected_p = metadata.get('expected_p_value', 0.54)
    tolerance = metadata.get('tolerance_mean', 2.0)
    tolerance_p = metadata.get('tolerance_p', 0.1)

    # 1. Retrieve Result JSON from Container
    # Note: Path must match what is in export_result.ps1
    # Since container is Windows, paths are like 'C:\Users\Docker\Documents\task_result.json'
    win_result_path = r"C:\Users\Docker\Documents\task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(win_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or parse result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify HTML Output (30 points)
    if result.get('html_exists') and result.get('html_valid'):
        if result.get('html_created_during_task'):
            score += 30
            feedback.append("HTML output generated successfully.")
        else:
            score += 10
            feedback.append("HTML output exists but timestamp suggests it wasn't created during this task.")
    else:
        feedback.append("HTML output missing or empty.")

    # 3. Verify Summary File & Content (50 points)
    summary_content = result.get('summary_content', [])
    summary_valid = False
    
    if result.get('summary_exists') and len(summary_content) >= 3:
        try:
            # Parse values from the first 3 lines
            # Allow for some text, try to extract floats
            import re
            def extract_float(text):
                matches = re.findall(r"[-+]?\d*\.\d+|\d+", str(text))
                return float(matches[0]) if matches else None

            val_yes = extract_float(summary_content[0])
            val_no = extract_float(summary_content[1])
            val_p = extract_float(summary_content[2])

            # Check Values
            stats_score = 0
            
            # Mean Yes
            if val_yes is not None and abs(val_yes - expected_mean_yes) <= tolerance:
                stats_score += 15
                feedback.append(f"Mean (Ill=Yes) correct: {val_yes}")
            else:
                feedback.append(f"Mean (Ill=Yes) incorrect: found {val_yes}, expected ~{expected_mean_yes}")

            # Mean No
            if val_no is not None and abs(val_no - expected_mean_no) <= tolerance:
                stats_score += 15
                feedback.append(f"Mean (Ill=No) correct: {val_no}")
            else:
                feedback.append(f"Mean (Ill=No) incorrect: found {val_no}, expected ~{expected_mean_no}")

            # P-Value
            if val_p is not None and abs(val_p - expected_p) <= tolerance_p:
                stats_score += 15
                feedback.append(f"P-value correct: {val_p}")
            else:
                feedback.append(f"P-value incorrect: found {val_p}, expected ~{expected_p}")
            
            # Significance Label (Line 4)
            if len(summary_content) >= 4:
                line4 = summary_content[3].lower()
                is_sig = val_p is not None and val_p < 0.05
                expected_label = "significant" if is_sig else "not significant"
                
                if expected_label in line4:
                    stats_score += 5
                    feedback.append("Significance conclusion correct.")
                elif "significant" in line4 and not is_sig:
                     feedback.append("Significance conclusion incorrect (false positive).")
            
            score += stats_score
            if stats_score > 20: 
                summary_valid = True

        except Exception as e:
            feedback.append(f"Error parsing summary file content: {e}")
    else:
        feedback.append("Summary file missing or has insufficient lines.")

    # 4. Verify App State (10 points)
    if result.get('app_running'):
        score += 10
        feedback.append("Epi Info Analysis is running.")
    else:
        feedback.append("Epi Info Analysis was not running at end of task.")

    # 5. VLM / Trajectory Check (10 points)
    # Simple check: did we get points from files? If so, assume interaction happened.
    # A full VLM check would be better but requires the `query_vlm` function which is standard in this framework.
    # We will grant these points if the summary data is correct, as that implies usage.
    if summary_valid:
        score += 10
        feedback.append("Implicit verification: Correct data values imply tool usage.")

    passed = score >= 60 and summary_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }