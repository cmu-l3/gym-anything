#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hierarchical_regression_exam(traj, env_info, task_info):
    """
    Verifies the hierarchical regression task.
    1. Parses the text report for correct statistical values.
    2. Checks existence and freshness of the .omv project file.
    3. Uses VLM to verify the hierarchical block structure in the UI history.
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []
    
    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify Output Files (File-based verification)
    
    # Check Project File (.omv)
    if result_data.get("omv_exists") and result_data.get("omv_fresh"):
        if result_data.get("omv_size", 0) > 5000: # Empty file is usually ~1-2kb
            score += 10
            feedback.append("Project file saved correctly.")
        else:
            feedback.append("Project file is too small (likely empty).")
    else:
        feedback.append("Project file missing or not saved during task.")

    # Check Report File
    report_parsed = {}
    if result_data.get("report_exists") and result_data.get("report_fresh"):
        try:
            content = base64.b64decode(result_data.get("report_content_b64", "")).decode('utf-8')
            score += 10 # File exists and is fresh
            
            # Parse lines
            for line in content.splitlines():
                if '=' in line:
                    key, val = line.split('=', 1)
                    report_parsed[key.strip()] = val.strip()
            
            feedback.append("Report file found and readable.")
        except Exception as e:
            feedback.append(f"Error reading report file: {str(e)}")
    else:
        feedback.append("Report file missing or stale.")

    # 3. Verify Statistical Values
    expected = task_info.get('metadata', {}).get('expected_values', {})
    
    # Helper for numeric checks
    def check_val(key, val_str, points):
        try:
            val = float(val_str)
            target = expected[key]
            if target['min'] <= val <= target['max']:
                return points, f"{key} correct."
            else:
                return 0, f"{key} out of range (Got {val}, expected {target['min']}-{target['max']})."
        except ValueError:
            return 0, f"{key} is not a valid number."
        except KeyError:
            return 0, f"{key} missing from metadata."

    if report_parsed:
        # Check Model 1 R2
        p, msg = check_val("Model1_R2", report_parsed.get("Model1_R2"), 15)
        score += p; feedback.append(msg)
        
        # Check Model 2 R2
        p, msg = check_val("Model2_R2", report_parsed.get("Model2_R2"), 15)
        score += p; feedback.append(msg)
        
        # Check R2 Change
        p, msg = check_val("R2_Change", report_parsed.get("R2_Change"), 15)
        score += p; feedback.append(msg)
        
        # Check Coefficients
        p, msg = check_val("Revise_B", report_parsed.get("Revise_B"), 10)
        score += p; feedback.append(msg)
        
        p, msg = check_val("Anxiety_B_Model2", report_parsed.get("Anxiety_B_Model2"), 10)
        score += p; feedback.append(msg)
        
        # Check Significance
        sig = report_parsed.get("R2_Change_Significant", "").lower()
        if sig == "yes":
            score += 10
            feedback.append("Significance identified correctly.")
        else:
            feedback.append(f"Significance incorrect (Got '{sig}', expected 'yes').")

    # 4. VLM Verification (Trajectory Analysis)
    # Check if the UI actually showed 2 blocks/models being created
    
    frames = sample_trajectory_frames(traj, n=4)
    final_ss = get_final_screenshot(traj)
    
    if frames or final_ss:
        prompt = """
        Analyze these screenshots of a Jamovi Regression analysis.
        I am looking for evidence of a "Hierarchical" or "Block-wise" regression.
        
        Look for:
        1. The "Model Builder" panel showing "Block 1" and "Block 2".
        2. A "Model Fit Measures" table showing results for "Model 1" and "Model 2" (two rows).
        3. A "Model Comparisons" or "Model Change" table.
        
        Does the user appear to have created two distinct models/blocks?
        Return JSON: {"hierarchical_structure_visible": boolean}
        """
        
        vlm_res = query_vlm(
            images=frames + ([final_ss] if final_ss else []),
            prompt=prompt
        )
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('hierarchical_structure_visible'):
                score += 5
                feedback.append("VLM confirmed hierarchical model structure in UI.")
            else:
                feedback.append("VLM could not confirm hierarchical structure (blocks) in screenshots.")
        else:
            # If VLM fails, we don't penalize, just don't award the bonus 5 points
            # or we can treat the high data accuracy as sufficient proof.
            feedback.append("VLM verification skipped due to error.")

    # 5. Final Scoring
    passed = score >= 60
    # Mandatory requirement: Must have at least attempted the report with some valid numbers
    if "Model1_R2 correct." not in feedback and "Model2_R2 correct." not in feedback:
        passed = False
        feedback.append("FAILED: Critical accuracy thresholds for R² values not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }