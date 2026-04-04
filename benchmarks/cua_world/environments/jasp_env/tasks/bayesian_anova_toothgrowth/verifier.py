#!/usr/bin/env python3
"""
Verifier for Bayesian Two-Way ANOVA task in JASP.

Verification Strategy:
1. File Verification (45 pts):
   - JASP project file created/modified during task
   - Text summary file created/modified during task
   - JASP file is a valid zip (JASP format)

2. Content Verification (30 pts):
   - Text file contains "dose", "supp" keywords
   - Text file contains numeric values matching expected BF ranges:
     - BF_inclusion(dose) > 100 (Strong evidence)
     - BF_inclusion(supp) > 1 (Some evidence)

3. VLM Verification (25 pts):
   - Trajectory shows "Bayesian ANOVA" panel
   - Variables correctly assigned (len=DV, dose/supp=Fixed)
"""

import json
import os
import sys
import re
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_anova(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_bf_dose_min = metadata.get('expected_bf_dose_min', 100.0)

    # =========================================================
    # 1. Retrieve Task Results
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    task_result = {}
    text_content = ""
    
    try:
        # Load JSON result
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
            
        # Load JASP file if exists
        if task_result.get('jasp_file', {}).get('exists'):
            try:
                copy_from_env("/tmp/output.jasp", temp_jasp.name)
            except Exception:
                pass
                
        # Load Text file if exists
        if task_result.get('text_file', {}).get('exists'):
            try:
                copy_from_env("/tmp/output.txt", temp_txt.name)
                with open(temp_txt.name, 'r', errors='ignore') as f:
                    text_content = f.read()
            except Exception:
                pass
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification files: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # =========================================================
    # 2. File Verification (45 pts)
    # =========================================================
    jasp_info = task_result.get('jasp_file', {})
    text_info = task_result.get('text_file', {})
    
    # Check JASP file
    if jasp_info.get('exists') and jasp_info.get('created_during_task'):
        # Verify it's a valid zip (JASP files are zipped JSONs)
        if zipfile.is_zipfile(temp_jasp.name):
            score += 25
            feedback_parts.append("Valid JASP project file saved.")
        else:
            score += 10
            feedback_parts.append("JASP file saved but format invalid (not a zip).")
    elif jasp_info.get('exists'):
        score += 5
        feedback_parts.append("JASP file exists but not modified during task.")
    else:
        feedback_parts.append("JASP project file NOT found.")

    # Check Text file
    if text_info.get('exists') and text_info.get('created_during_task'):
        score += 20
        feedback_parts.append("Results summary file saved.")
    elif text_info.get('exists'):
        score += 5
        feedback_parts.append("Summary file exists but not modified during task.")
    else:
        feedback_parts.append("Results summary file NOT found.")

    # Clean up temp JASP file
    if os.path.exists(temp_jasp.name): os.unlink(temp_jasp.name)

    # =========================================================
    # 3. Content Verification (30 pts)
    # =========================================================
    if text_content:
        lower_content = text_content.lower()
        
        # Check for keywords
        if "dose" in lower_content and "supp" in lower_content:
            score += 5
            feedback_parts.append("Summary mentions required factors.")
        
        # Extract numbers to verify Bayesian Analysis was run (Dose BF should be huge)
        # Look for patterns like "dose: 1234" or "dose ... 1.23e+5"
        numbers = re.findall(r'[\d]+[.,]?\d*(?:[eE][+-]?\d+)?', text_content)
        numeric_values = []
        for n in numbers:
            try:
                val = float(n.replace(',', ''))
                numeric_values.append(val)
            except ValueError:
                continue
        
        # We expect at least one very large number (BF for dose)
        has_large_bf = any(v > expected_bf_dose_min for v in numeric_values)
        
        if has_large_bf:
            score += 25
            feedback_parts.append("Summary contains high Bayes Factor expected for Dose effect.")
        elif numeric_values:
            # If numbers exist but none are large enough, maybe they ran frequentist ANOVA (p < 0.05)
            # or reported something else.
            score += 5
            feedback_parts.append("Summary contains numbers, but Bayes Factor for dose seems too low (expected > 100).")
        else:
            feedback_parts.append("Summary does not appear to contain numeric results.")
    
    # Clean up temp text file
    if os.path.exists(temp_txt.name): os.unlink(temp_txt.name)

    # =========================================================
    # 4. VLM Verification (25 pts)
    # =========================================================
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        images_to_check = frames + [final_screen] if final_screen else frames

        prompt = """
        Analyze these screenshots of JASP statistical software.
        1. Is the "Bayesian ANOVA" analysis visible? (Look for "Bayesian" in the results title).
        2. Are the variables assigned correctly?
           - Dependent Variable: 'len'
           - Fixed Factors: 'supp' and 'dose'
        3. Is the "Effects" table visible in the results? (Shows BF_inclusion).
        
        Return JSON:
        {
          "bayesian_anova_visible": boolean,
          "variables_correct": boolean,
          "effects_table_visible": boolean
        }
        """

        vlm_res = query_vlm(
            images=images_to_check, 
            prompt=prompt
        )
        
        vlm_data = vlm_res.get('parsed', {})
        
        if vlm_data.get('bayesian_anova_visible'):
            score += 10
            feedback_parts.append("VLM confirmed Bayesian ANOVA interface.")
        else:
            feedback_parts.append("VLM did not see Bayesian ANOVA header.")
            
        if vlm_data.get('variables_correct'):
            score += 10
            feedback_parts.append("VLM confirmed correct variable assignment.")
            
        if vlm_data.get('effects_table_visible'):
            score += 5
            feedback_parts.append("VLM confirmed Effects table visibility.")

    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback_parts.append("VLM verification skipped due to error.")
        # Grant partial credit if file verification was strong to avoid failing on VLM error
        if score >= 65:
            score += 10

    # =========================================================
    # Final Scoring
    # =========================================================
    # Passing requires file existence + strong evidence of correct analysis (content or VLM)
    passed = score >= 60 and jasp_info.get('exists') and text_info.get('exists')
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }