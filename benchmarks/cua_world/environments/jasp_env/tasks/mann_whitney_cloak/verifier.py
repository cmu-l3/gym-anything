#!/usr/bin/env python3
"""
Verifier for Mann-Whitney U Test Task (mann_whitney_cloak@1).

Criteria:
1. Report file exists and contains correct statistics (W, p, effect size).
2. JASP project file exists and was saved during the task.
3. VLM Verification:
   - Confirms proper Mann-Whitney test selection (not T-Test).
   - Confirms Descriptives/Plots enabled.
"""

import json
import os
import re
import sys
import base64
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_mann_whitney_cloak(traj, env_info, task_info):
    """
    Verify completion of the Mann-Whitney U test task.
    """
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Import VLM utils if available
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        vlm_available = True
    except ImportError:
        logger.warning("VLM modules not available. Skipping visual verification steps.")
        vlm_available = False

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize Score
    score = 0
    max_score = 100
    feedback = []
    
    # Metadata targets
    meta = task_info.get('metadata', {}).get('expected_values', {})
    w_min = meta.get('w_statistic_min', 30.0)
    w_max = meta.get('w_statistic_max', 120.0)
    p_min = meta.get('p_value_min', 0.05)
    p_max = meta.get('p_value_max', 0.25)
    
    # =========================================================
    # CRITERION 1: REPORT CONTENT (45 points)
    # =========================================================
    report_info = result.get('report_file', {})
    report_exists = report_info.get('exists', False)
    
    if report_exists:
        score += 5
        feedback.append("Report file created.")
        
        # Decode content
        try:
            content = base64.b64decode(report_info.get('content_base64', '')).decode('utf-8', errors='ignore')
        except:
            content = ""
            
        # Check W statistic (e.g., "W = 89.5" or "U = 30")
        w_match = re.search(r'[WU]\s*[=:]\s*([\d.]+)', content, re.IGNORECASE)
        if w_match:
            try:
                w_val = float(w_match.group(1))
                if w_min <= w_val <= w_max:
                    score += 15
                    feedback.append(f"Correct W statistic found ({w_val}).")
                else:
                    score += 5
                    feedback.append(f"W statistic found but out of expected range ({w_val}).")
            except:
                feedback.append("Could not parse W statistic value.")
        else:
            feedback.append("Missing test statistic (W/U) in report.")

        # Check P-value
        p_match = re.search(r'p[\s-]*(?:val(?:ue)?)?\s*[=:<]\s*([\d.]+(?:e-?\d+)?)', content, re.IGNORECASE)
        if p_match:
            try:
                p_val = float(p_match.group(1))
                if p_min <= p_val <= p_max:
                    score += 15
                    feedback.append(f"Correct p-value found ({p_val}).")
                else:
                    # Partial credit if they found a p-value but maybe rounded weirdly
                    score += 5
                    feedback.append(f"P-value found but out of range ({p_val}).")
            except:
                pass
        else:
            feedback.append("Missing p-value in report.")

        # Check Effect Size (Rank Biserial)
        if re.search(r'(rank\s*biserial|correlation|effect\s*size)', content, re.IGNORECASE):
            score += 10
            feedback.append("Effect size reported.")
        else:
            feedback.append("Missing effect size in report.")

    else:
        feedback.append("Report file NOT found.")

    # =========================================================
    # CRITERION 2: JASP PROJECT FILE (20 points)
    # =========================================================
    proj_info = result.get('project_file', {})
    if proj_info.get('exists', False):
        if proj_info.get('size_bytes', 0) > 2000: # JASP files are usually >2KB even empty
            score += 10
            feedback.append("JASP project file saved.")
            
            if proj_info.get('created_during_task', False):
                score += 10
                feedback.append("Project file timestamp is valid (created during task).")
            else:
                feedback.append("WARNING: Project file timestamp predates task.")
        else:
            score += 5
            feedback.append("JASP file exists but is suspiciously small.")
    else:
        feedback.append("JASP project file NOT found.")

    # =========================================================
    # CRITERION 3: VISUAL VERIFICATION (35 points)
    # =========================================================
    if vlm_available and traj:
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = """
        Review these screenshots of a JASP statistical analysis session.
        1. Did the user select the "Mann-Whitney U" test (also called Wilcoxon rank-sum)? Look for "Mann-Whitney" in the results table or sidebar checkboxes.
        2. Are "Descriptives" (Group, N, Mean, SD) visible in the output?
        3. Is "Rank biserial correlation" visible in the output table?
        
        Answer with a JSON object:
        {
            "mann_whitney_selected": boolean,
            "descriptives_visible": boolean,
            "effect_size_visible": boolean,
            "reasoning": "string"
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res and isinstance(vlm_res, dict):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('mann_whitney_selected', False):
                score += 15
                feedback.append("VLM: Mann-Whitney test confirmed.")
            else:
                feedback.append("VLM: Could not visually confirm Mann-Whitney test.")
                
            if parsed.get('descriptives_visible', False):
                score += 10
                feedback.append("VLM: Descriptives confirmed.")
                
            if parsed.get('effect_size_visible', False):
                score += 10
                feedback.append("VLM: Effect size confirmed.")
    else:
        # Fallback if VLM not available or no trajectory
        feedback.append("Skipping visual verification (no trajectory or VLM).")
        # Scale remaining points so user isn't penalized for infrastructure missing
        # If we scored X out of 65 available, scaled = (X/65)*100
        if score > 0:
            score = int((score / 65) * 100)

    # =========================================================
    # FINAL RESULT
    # =========================================================
    
    # Pass logic: Must have report with correct stats OR high score from VLM + Project
    passed = score >= 60 and report_exists and w_match is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }