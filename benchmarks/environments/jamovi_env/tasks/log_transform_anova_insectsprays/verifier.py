#!/usr/bin/env python3
"""
Verifier for log_transform_anova_insectsprays task.

Verifies:
1. Valid OMV project file created.
2. Report file contains correct F-statistic, p-value, and significant difference count.
3. VLM verification of trajectory (Computed variable creation, ANOVA table).
"""

import json
import os
import tempfile
import base64
import logging
import re
import zipfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_transform_anova(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_f = metadata.get('expected_f', 46.006)
    f_tolerance = metadata.get('f_tolerance', 0.5)
    expected_count = metadata.get('expected_sig_diff_count', 3)

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify OMV File (Project Save)
    omv_exists = result.get('omv_exists', False)
    omv_created = result.get('omv_created_during_task', False)
    
    if omv_exists and omv_created:
        score += 10
        feedback_parts.append("Project file saved.")
        
        # Optional: Inspect OMV structure (it's a zip)
        # We try to copy it out to verify it's a valid zip
        try:
            temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
            copy_from_env(metadata.get('output_omv_path'), temp_omv.name)
            if zipfile.is_zipfile(temp_omv.name):
                score += 5  # Valid file format
                # We could inspect 'meta' inside but simply being a valid omv is good evidence
            os.unlink(temp_omv.name)
        except:
            pass
    else:
        feedback_parts.append("Project file not saved or not new.")

    # 3. Verify Report Content
    report_exists = result.get('report_exists', False)
    report_content_b64 = result.get('report_content_b64', "")
    
    f_stat_correct = False
    count_correct = False
    p_val_correct = False

    if report_exists and report_content_b64:
        try:
            content = base64.b64decode(report_content_b64).decode('utf-8')
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            
            # Check F-statistic (Line 1 expected)
            # Allow searching in first few lines
            found_f = False
            for line in lines:
                # Look for number near 46.0
                floats = re.findall(r"[-+]?\d*\.\d+|\d+", line)
                for num_str in floats:
                    try:
                        val = float(num_str)
                        if abs(val - expected_f) <= f_tolerance:
                            found_f = True
                            break
                    except:
                        pass
                if found_f: break
            
            if found_f:
                score += 25
                f_stat_correct = True
                feedback_parts.append(f"F-statistic correct (~{expected_f}).")
            else:
                feedback_parts.append(f"F-statistic incorrect or not found (Expected ~{expected_f}).")

            # Check p-value (Line 2 expected)
            # Looking for < .001 or 0.000 or very small number
            found_p = False
            if "0.001" in content or "0.000" in content or "< .001" in content or "<.001" in content:
                found_p = True
            
            if found_p:
                score += 15
                p_val_correct = True
                feedback_parts.append("p-value correct.")
            else:
                feedback_parts.append("p-value incorrect.")

            # Check Significant Count (Line 3 expected)
            # Looking for '3'
            found_count = False
            for line in lines:
                if "3" in line: # Simple check, or regex for "3" as a distinct word
                     if re.search(r'\b3\b', line):
                         found_count = True
                         break
            
            if found_count:
                score += 30
                count_correct = True
                feedback_parts.append("Significant difference count correct (3).")
            else:
                feedback_parts.append("Significant difference count incorrect (Expected 3).")

        except Exception as e:
            feedback_parts.append(f"Error parsing report: {e}")
    else:
        feedback_parts.append("Report file not found.")

    # 4. VLM Verification (Trajectory)
    # Check for visual evidence of "Compute" variable or "LN" formula usage
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_score = 0
    if frames:
        prompt = """
        Analyze these screenshots of a user using Jamovi.
        I am looking for evidence of two specific actions:
        1. Creating a Computed Variable (look for a formula box, 'Compute', or 'LN' function).
        2. Running an ANOVA (look for an ANOVA table, 'One-Way ANOVA', or p-values).
        
        Answer JSON:
        {
          "computed_variable_seen": true/false,
          "anova_table_seen": true/false,
          "post_hoc_seen": true/false
        }
        """
        try:
            res = query_vlm(prompt=prompt, images=frames + [final_shot])
            parsed = res.get('parsed', {})
            
            if parsed.get('computed_variable_seen'):
                vlm_score += 10
            if parsed.get('anova_table_seen'):
                vlm_score += 5
                
            feedback_parts.append(f"VLM Analysis: Compute={parsed.get('computed_variable_seen')}, ANOVA={parsed.get('anova_table_seen')}")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback points if files are perfect
            if f_stat_correct and count_correct:
                vlm_score += 15

    score += vlm_score

    # Final tally
    passed = (score >= 60) and (f_stat_correct or count_correct)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }