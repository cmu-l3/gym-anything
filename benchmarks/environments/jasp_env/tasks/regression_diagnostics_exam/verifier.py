#!/usr/bin/env python3
"""
Verifier for regression_diagnostics_exam task.

Verifies:
1. JASP project file creation (anti-gaming check).
2. Report file creation and content (VIF and Part Correlation values).
3. VLM verification of the final screenshot to confirm specific JASP output tables.
"""

import json
import os
import tempfile
import logging
import re
import zipfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regression_diagnostics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})

    # Ground truth ranges (approximate for ExamAnxiety dataset)
    # VIF for Anxiety is typically ~1.0-1.1 (low collinearity)
    # Part Correlation for Anxiety is typically ~ -0.2 to -0.3
    vif_min = ground_truth.get("anxiety_vif_min", 1.0)
    vif_max = ground_truth.get("anxiety_vif_max", 1.5)
    part_min = ground_truth.get("anxiety_part_corr_min", -0.5)
    part_max = ground_truth.get("anxiety_part_corr_max", -0.1)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check JASP File (30 pts)
    # Must exist, be created during task, and be a valid zip
    jasp_exists = result_data.get('jasp_file_exists', False)
    jasp_fresh = result_data.get('jasp_file_created_during_task', False)
    jasp_size = result_data.get('jasp_file_size', 0)

    if jasp_exists and jasp_fresh and jasp_size > 1000:
        # Additional check: retrieve the .jasp file and verify it's a valid zip
        try:
            temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
            copy_from_env("/home/ga/Documents/JASP/RegressionDiagnostics.jasp", temp_jasp.name)
            if zipfile.is_zipfile(temp_jasp.name):
                score += 30
                feedback_parts.append("Valid JASP project file created.")
            else:
                score += 10
                feedback_parts.append("JASP file exists but is not a valid archive.")
            os.unlink(temp_jasp.name)
        except:
            score += 15
            feedback_parts.append("JASP file created (validation failed).")
    elif jasp_exists:
        feedback_parts.append("JASP file exists but was not modified during task.")
    else:
        feedback_parts.append("JASP project file not found.")

    # 3. Check Report Content (40 pts)
    report_exists = result_data.get('report_file_exists', False)
    report_content = result_data.get('report_content', "")
    
    vif_found = False
    part_found = False
    
    if report_exists:
        score += 10 # For creating the file
        
        # Parse VIF using regex
        # Looking for "VIF" followed by numbers
        vif_match = re.search(r'VIF.*?(\d+\.?\d*)', report_content, re.IGNORECASE)
        if vif_match:
            try:
                vif_val = float(vif_match.group(1))
                if vif_min <= vif_val <= vif_max:
                    score += 15
                    vif_found = True
                    feedback_parts.append(f"VIF value correct ({vif_val}).")
                else:
                    score += 5
                    feedback_parts.append(f"VIF value found ({vif_val}) but outside expected range ({vif_min}-{vif_max}).")
            except:
                feedback_parts.append("Could not parse VIF number.")
        else:
            feedback_parts.append("VIF value not found in report.")

        # Parse Part Correlation
        # Looking for "Part" or "Partial" followed by optional negative sign and numbers
        part_match = re.search(r'Part.*?(-?\d+\.?\d*)', report_content, re.IGNORECASE)
        if part_match:
            try:
                part_val = float(part_match.group(1))
                # Part correlation for Anxiety should be negative
                if part_min <= part_val <= part_max:
                    score += 15
                    part_found = True
                    feedback_parts.append(f"Part correlation correct ({part_val}).")
                else:
                    score += 5
                    feedback_parts.append(f"Part correlation found ({part_val}) but outside expected range.")
            except:
                feedback_parts.append("Could not parse Part correlation number.")
        else:
            feedback_parts.append("Part correlation not found in report.")
            
    else:
        feedback_parts.append("Report file not found.")

    # 4. VLM Verification (30 pts)
    # Check if the Coefficients table with VIF and Part/Partial cols is visible
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        prompt = """
        Analyze this JASP screenshot. 
        1. Is a "Coefficients" table visible?
        2. Does the table contain a "Collinearity Statistics" section or "VIF" column?
        3. Does the table contain "Part" and "Partial" correlation columns?
        4. Are the rows "Anxiety" and "Revise" visible?
        """
        
        vlm_res = query_vlm(
            prompt=prompt,
            image=final_screenshot,
            criterias=[
                "coefficients_table_visible",
                "vif_column_visible",
                "part_partial_visible"
            ]
        )
        
        criteria = vlm_res.get('criteria', {})
        if criteria.get('coefficients_table_visible'): vlm_score += 10
        if criteria.get('vif_column_visible'): vlm_score += 10
        if criteria.get('part_partial_visible'): vlm_score += 10
        
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append(f"VLM verified visual output ({vlm_score}/30 pts).")
        else:
            feedback_parts.append("VLM did not detect required statistics tables.")

    # Final scoring
    passed = (score >= 75) and jasp_exists and (vif_found or part_found)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }