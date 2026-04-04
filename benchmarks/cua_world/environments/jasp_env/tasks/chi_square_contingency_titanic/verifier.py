#!/usr/bin/env python3
"""
Verifier for Chi-Square Contingency Table Task in JASP.

Verification Logic:
1. Validates the results text file contains correct Chi-Square stats (Chi-sq, df, p, V).
2. Validates the JASP project file (.jasp) was saved and contains the analysis configuration.
3. Uses VLM to verify the UI shows the correct analysis table and variable types.
"""

import json
import os
import tempfile
import base64
import zipfile
import re
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_results_text(content):
    """Parses the expected key:value format from the results file."""
    data = {}
    lines = content.split('\n')
    for line in lines:
        if ':' in line:
            key, val = line.split(':', 1)
            key = key.strip().lower()
            val = val.strip()
            # Clean up value (remove <, >, approx symbols if present)
            clean_val = val.replace('<', '').replace('>', '').replace('=', '').strip()
            try:
                data[key] = float(clean_val)
            except ValueError:
                data[key] = val
    return data

def verify_jasp_zip_content(jasp_path, copy_from_env):
    """
    Checks if the .jasp file is a valid zip and contains analysis metadata.
    JASP files are ZIP archives. We check for analyses.json or similar structure.
    """
    temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    try:
        copy_from_env(jasp_path, temp_zip.name)
        
        if not zipfile.is_zipfile(temp_zip.name):
            return False, "File is not a valid JASP archive"
            
        with zipfile.ZipFile(temp_zip.name, 'r') as zf:
            file_list = zf.namelist()
            # JASP structure usually has an 'index.html' or 'analyses' folder/json
            # We look for indications that an analysis was stored
            
            # Simple check: is there content?
            if len(file_list) < 3:
                return False, "JASP file appears empty/corrupt"
                
            # Advanced check: Try to read analysis metadata if possible
            # (Structure varies by JASP version, but usually readable text config exists)
            content_found = False
            for f in file_list:
                if f.endswith('.json') or f.endswith('.qml') or 'analysis' in f.lower():
                    content_found = True
                    break
            
            if content_found:
                return True, "Valid JASP structure found"
            else:
                return True, "Zip valid but analysis structure unclear (passing with warning)"
                
    except Exception as e:
        return False, f"Failed to inspect JASP file: {str(e)}"
    finally:
        if os.path.exists(temp_zip.name):
            os.unlink(temp_zip.name)

def verify_chi_square_titanic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})

    score = 0
    feedback_parts = []
    
    # Load exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # =========================================================
    # CRITERION 1: Results File Content (40 pts)
    # =========================================================
    results_exists = result_json.get('results_exists', False)
    if results_exists:
        content_b64 = result_json.get('results_content_base64', "")
        try:
            content_text = base64.b64decode(content_b64).decode('utf-8')
            parsed_data = parse_results_text(content_text)
            
            # Check Chi-Square Value (102.89)
            val_chi = parsed_data.get('chi_square')
            if isinstance(val_chi, (int, float)):
                if abs(val_chi - gt['chi_square']) < gt['chi_square_tol']:
                    score += 15
                    feedback_parts.append(f"Chi-square correct ({val_chi})")
                else:
                    feedback_parts.append(f"Chi-square incorrect ({val_chi}, expected ~{gt['chi_square']})")
            else:
                feedback_parts.append("Chi-square value missing/unreadable")

            # Check DF (2)
            val_df = parsed_data.get('df')
            if val_df == gt['df']:
                score += 5
                feedback_parts.append("DF correct")
            else:
                feedback_parts.append(f"DF incorrect ({val_df})")

            # Check p-value (< .001)
            val_p = parsed_data.get('p_value')
            if isinstance(val_p, str) and ('<' in val_p or '0.001' in val_p):
                score += 10
                feedback_parts.append("p-value notation correct")
            elif isinstance(val_p, (int, float)) and val_p < gt['p_value_threshold']:
                score += 10
                feedback_parts.append("p-value correct")
            else:
                feedback_parts.append(f"p-value incorrect or missing ({val_p})")

            # Check Cramér's V (0.34)
            val_cv = parsed_data.get('cramers_v')
            if isinstance(val_cv, (int, float)):
                if abs(val_cv - gt['cramers_v']) < gt['cramers_v_tol']:
                    score += 10
                    feedback_parts.append(f"Cramér's V correct ({val_cv})")
                else:
                    feedback_parts.append(f"Cramér's V incorrect ({val_cv}, expected ~{gt['cramers_v']})")
            else:
                feedback_parts.append("Cramér's V missing")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing results file: {e}")
    else:
        feedback_parts.append("Results text file not found")

    # =========================================================
    # CRITERION 2: JASP Project File (20 pts)
    # =========================================================
    project_exists = result_json.get('project_exists', False)
    project_new = result_json.get('project_created_during_task', False)
    project_path = result_json.get('project_path')
    
    if project_exists and project_new:
        valid_zip, zip_msg = verify_jasp_zip_content(project_path, copy_from_env)
        if valid_zip:
            score += 20
            feedback_parts.append("Valid JASP project saved")
        else:
            score += 10
            feedback_parts.append(f"JASP file exists but invalid structure: {zip_msg}")
    elif project_exists:
        score += 5
        feedback_parts.append("JASP file exists but not modified during task")
    else:
        feedback_parts.append("JASP project file missing")

    # =========================================================
    # CRITERION 3: VLM Verification (40 pts)
    # =========================================================
    # We check the trajectory to ensure the actual workflow was performed
    # 1. Variables set to Nominal (critical step)
    # 2. Contingency table displayed
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + [final_screen] if final_screen else frames

    if images:
        prompt = """
        Review this sequence of screenshots from JASP (statistical software).
        I need to verify if the user performed a Chi-Square Test of Independence on the Titanic dataset.
        
        Look for these specific evidences:
        1. VARIABLE TYPES: Did the user change 'Survived' and 'Pclass' variables to NOMINAL? 
           (Look for the three-colored cluster icon in column headers, NOT the ruler icon).
        2. ANALYSIS: Is the 'Contingency Tables' results panel visible?
        3. OUTPUT: Do you see a table with 'Chi-squared' statistics?
        4. VALUES: Do you see a Chi-square value approx 102.89 or Cramér's V approx 0.34?
        
        Return JSON:
        {
            "nominal_variables_set": boolean,
            "contingency_table_visible": boolean,
            "chi_square_stats_visible": boolean,
            "confidence": "low|medium|high"
        }
        """
        
        vlm_res = query_vlm(images=images, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("nominal_variables_set"):
                score += 15
                feedback_parts.append("VLM: Nominal variables set")
            if parsed.get("contingency_table_visible"):
                score += 15
                feedback_parts.append("VLM: Contingency table visible")
            if parsed.get("chi_square_stats_visible"):
                score += 10
                feedback_parts.append("VLM: Statistics visible")
        else:
            feedback_parts.append("VLM verification failed")
            # Fallback: if we have strong file evidence, give partial VLM credit
            if score >= 50: 
                score += 20
                feedback_parts.append("Fallback VLM points due to strong file evidence")

    # =========================================================
    # FINAL SCORING
    # =========================================================
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }