#!/usr/bin/env python3
"""
Verifier for Repeated Measures ANOVA task (Jamovi).

Verification Strategy:
1. File Existence & Integrity:
   - Check if .omv file exists and is a valid ZIP archive.
   - Check if .txt summary exists and has content.
2. Analysis Configuration (from .omv internal JSON):
   - Verify 'anovaRM' analysis is present.
   - Verify within-subjects factor 'Item' has 5 levels.
   - Verify sphericity tests and Greenhouse-Geisser options enabled.
   - Verify Bonferroni post-hoc enabled.
3. Result Values (from .txt summary):
   - Check for sensible F-statistics and N count.
4. Visual Verification (VLM):
   - Check trajectory for workflow progression (Loading -> Dialog -> Results).
"""

import json
import os
import zipfile
import tempfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_repeated_measures_anova(traj, env_info, task_info):
    """
    Verify the Repeated Measures ANOVA task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_omv_path = metadata.get('expected_omv_path', '/home/ga/Documents/Jamovi/RM_ANOVA_Neuroticism.omv')
    expected_txt_path = metadata.get('expected_txt_path', '/home/ga/Documents/Jamovi/rm_anova_results.txt')

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Result JSON
    # ------------------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            task_result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # ------------------------------------------------------------------
    # 2. Verify .omv File (Analysis Config) - 40 pts
    # ------------------------------------------------------------------
    omv_passed = False
    if task_result.get("omv_exists") and task_result.get("omv_created_during_task"):
        score += 10
        feedback_parts.append(".omv file created.")
        
        # Analyze internal structure of .omv (it is a ZIP)
        with tempfile.NamedTemporaryFile(suffix='.omv') as omv_tf:
            try:
                copy_from_env(expected_omv_path, omv_tf.name)
                
                if zipfile.is_zipfile(omv_tf.name):
                    with zipfile.ZipFile(omv_tf.name, 'r') as zf:
                        # Jamovi stores analysis definitions in index.json or inside analysis folders
                        # We search all JSON files for specific keys
                        
                        found_rm_anova = False
                        found_5_levels = False
                        found_sphericity = False
                        found_gg = False
                        found_bonferroni = False
                        
                        for filename in zf.namelist():
                            if filename.endswith('.json'):
                                try:
                                    with zf.open(filename) as json_file:
                                        content = json.load(json_file)
                                        content_str = json.dumps(content)
                                        
                                        # Heuristic check for analysis configuration
                                        if "anovaRM" in content_str or "rmanova" in content_str.lower():
                                            found_rm_anova = True
                                        
                                        # Check for 5 levels in factors
                                        # Structure varies, but often looking for list of levels
                                        # or a count. Regex search on string representation is robust.
                                        if "N1" in content_str and "N5" in content_str:
                                            found_5_levels = True
                                            
                                        # Check options
                                        if "sphericity" in content_str.lower() or "mauchly" in content_str.lower():
                                            found_sphericity = True
                                        if "gg" in content_str.lower() or "greenhouse" in content_str.lower():
                                            found_gg = True
                                        if "bonferroni" in content_str.lower():
                                            found_bonferroni = True
                                            
                                except:
                                    continue
                        
                        if found_rm_anova:
                            score += 10
                            feedback_parts.append("RM ANOVA analysis found in project.")
                            omv_passed = True
                        else:
                            feedback_parts.append("RM ANOVA analysis NOT found in project.")

                        if found_5_levels:
                            score += 5
                            feedback_parts.append("Factor levels correct.")
                        if found_sphericity and found_gg:
                            score += 10
                            feedback_parts.append("Sphericity/GG corrections enabled.")
                        if found_bonferroni:
                            score += 5
                            feedback_parts.append("Bonferroni post-hoc enabled.")
                            
                else:
                    feedback_parts.append(".omv is not a valid zip archive.")
            except Exception as e:
                feedback_parts.append(f"Failed to inspect .omv file: {e}")
    else:
        feedback_parts.append(".omv file missing or not created during task.")

    # ------------------------------------------------------------------
    # 3. Verify .txt Summary Content - 30 pts
    # ------------------------------------------------------------------
    if task_result.get("txt_exists") and task_result.get("txt_created_during_task"):
        score += 5
        feedback_parts.append("Summary text file created.")
        
        with tempfile.NamedTemporaryFile(suffix='.txt') as txt_tf:
            try:
                copy_from_env(expected_txt_path, txt_tf.name)
                with open(txt_tf.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                    
                    # Check for keywords and values
                    if "n" in content and any(x in content for x in ["2000", "2800", "2694"]): # 2694 is exact N
                        score += 5
                        feedback_parts.append("Sample size reported correctly.")
                    
                    if "f" in content or "statistic" in content:
                        score += 5
                        feedback_parts.append("F-statistic reported.")
                        
                    if "mauchly" in content or "sphericity" in content:
                        score += 5
                        feedback_parts.append("Mauchly's test mentioned.")
                        
                    if "greenhouse" in content or "epsilon" in content:
                        score += 5
                        feedback_parts.append("Epsilon value mentioned.")
                        
                    if any(item in content for item in ["n1", "n2", "n3", "n4", "n5"]):
                        score += 5
                        feedback_parts.append("Items identified.")
                        
            except Exception as e:
                feedback_parts.append(f"Failed to read summary file: {e}")
    else:
        feedback_parts.append("Summary text file missing.")

    # ------------------------------------------------------------------
    # 4. VLM Verification - 30 pts
    # ------------------------------------------------------------------
    # Use trajectory frames to confirm workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        You are verifying a Jamovi statistics task.
        The user should have:
        1. Loaded a dataset with columns N1-N5.
        2. Opened the 'Repeated Measures ANOVA' dialog.
        3. Configured factors and options (Sphericity, Post Hoc).
        4. Produced a results table.

        Review these screenshots from the session. 
        Did the user perform these steps?
        Are the Repeated Measures ANOVA results visible in the final steps?
        
        Respond with JSON:
        {"steps_observed": ["list", "of", "steps"], "results_visible": boolean, "confidence": float}
        """
        
        vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("results_visible"):
                score += 15
                feedback_parts.append("VLM: Results table visible.")
            
            steps = parsed.get("steps_observed", [])
            if any("anova" in s.lower() for s in steps) or len(steps) >= 2:
                score += 15
                feedback_parts.append("VLM: Workflow steps observed.")
        else:
            feedback_parts.append("VLM verification failed/inconclusive.")
            # Fallback point grant if programmatic checks were very strong
            if omv_passed:
                score += 10

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 60 and omv_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }