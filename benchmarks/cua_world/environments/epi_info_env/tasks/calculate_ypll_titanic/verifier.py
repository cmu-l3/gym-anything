#!/usr/bin/env python3
"""
Verifier for calculate_ypll_titanic task.

Checks:
1. Output file existence and freshness.
2. Content analysis (parsing the YPLL sum).
3. VLM verification of the process (Classic Analysis usage).
"""

import json
import os
import tempfile
import re
import logging
from vlm_utils import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_ypll_titanic(traj, env_info, task_info):
    """
    Verify the YPLL calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    result_data = {}
    report_content = ""
    
    try:
        # Copy result metadata
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Copy actual report file if it exists
        if result_data.get("output_exists"):
            output_path = result_data.get("output_path", "C:\\Users\\Docker\\Documents\\EpiAnalysis\\ypll_report.txt")
            try:
                copy_from_env(output_path, temp_report.name)
                with open(temp_report.name, 'r', errors='ignore') as f:
                    report_content = f.read()
            except Exception as e:
                logger.warning(f"Could not copy report file: {e}")
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Report File Created (20 pts)
    # ---------------------------------------------------------
    if result_data.get("output_exists"):
        score += 10
        if result_data.get("file_created_during_task"):
            score += 10
            feedback_parts.append("New report file created")
        else:
            feedback_parts.append("Report file exists but timestamp is old")
    else:
        feedback_parts.append("No report file found")
        
    # ---------------------------------------------------------
    # Criterion 2: Value Verification (40 pts)
    # ---------------------------------------------------------
    ground_truth = result_data.get("ground_truth_ypll", 18235.0) # Default fallback
    # The sum should be roughly 18255 based on standard Titanic dataset
    
    # Parse report for the sum
    # Look for patterns like "Sum", "Total", and the number
    # Epi Info output usually has headers. We look for a large number near "YPLL"
    
    found_val = False
    extracted_val = 0.0
    
    if report_content:
        # Find all numbers in the report
        # Filter for numbers that are plausibly the sum (close to GT)
        numbers = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", report_content)]
        
        # Check specific Epi Info MEANS output patterns if possible, 
        # but robustly check if ANY number matches GT within tolerance.
        tolerance = task_info.get("metadata", {}).get("ground_truth_tolerance", 50)
        
        best_diff = float('inf')
        
        for num in numbers:
            diff = abs(num - ground_truth)
            if diff < best_diff:
                best_diff = diff
                extracted_val = num
                
        if best_diff <= tolerance:
            score += 40
            found_val = True
            feedback_parts.append(f"Correct YPLL Sum found: {extracted_val} (GT: {ground_truth})")
        else:
            feedback_parts.append(f"Value mismatch. Closest found: {extracted_val} vs GT: {ground_truth}")
            # Partial credit if they calculated SOMETHING large (maybe forgot filter)
            if extracted_val > 1000: 
                score += 5
                feedback_parts.append("(Partial credit for calculating a sum)")

    # ---------------------------------------------------------
    # Criterion 3: VLM Process Verification (40 pts)
    # ---------------------------------------------------------
    # Check trajectory for:
    # 1. Titanic data loaded (10)
    # 2. Filter/Select applied (10)
    # 3. Define/Assign logic (10)
    # 4. Means/Result shown (10)
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = f"""
        Analyze these screenshots of a user working in Epi Info 7.
        Task: Calculate Years of Potential Life Lost (YPLL) for Titanic victims.
        
        Look for:
        1. 'READ' command or data grid showing Titanic passenger data.
        2. 'SELECT' or filter usage (Survived=0).
        3. 'DEFINE' YPLL or 'ASSIGN' calculation (75 - Age).
        4. 'MEANS' command or statistical output results.
        
        Return JSON with boolean keys: data_loaded, filter_applied, calculation_logic, results_shown.
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('data_loaded'): vlm_score += 10
        if parsed.get('filter_applied'): vlm_score += 10
        if parsed.get('calculation_logic'): vlm_score += 10
        if parsed.get('results_shown'): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"VLM verification score: {vlm_score}/40")
    else:
        feedback_parts.append("No trajectory frames for VLM")

    # Final Check
    passed = (score >= 70) and found_val
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }