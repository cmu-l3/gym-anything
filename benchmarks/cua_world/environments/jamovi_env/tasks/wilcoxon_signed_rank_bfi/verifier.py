#!/usr/bin/env python3
"""
Verifier for wilcoxon_signed_rank_bfi task.
Verifies:
1. Result files exist and were created during task.
2. Reported statistics (W, p, effect size) match ground truth.
3. .omv project file is valid and contains data.
4. VLM verifies UI interaction (Wilcoxon selected, Descriptives shown).
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wilcoxon_signed_rank_bfi(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Retrieve Files ---
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    omv_local_path = os.path.join(temp_dir, "project.omv")
    txt_local_path = os.path.join(temp_dir, "results.txt")
    gt_local_path = os.path.join(temp_dir, "ground_truth.txt")

    try:
        # Get result metadata
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            res_meta = json.load(f)

        # Get actual result files if they exist
        if res_meta.get("omv_exists"):
            copy_from_env(res_meta["omv_path"], omv_local_path)
        
        if res_meta.get("txt_exists"):
            copy_from_env(res_meta["txt_path"], txt_local_path)
            
        # Get ground truth
        copy_from_env(res_meta["ground_truth_path"], gt_local_path)

    except Exception as e:
        logger.error(f"File retrieval failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output files: {str(e)}"}

    # --- Initialize Score ---
    score = 0
    feedback = []
    
    # --- Criterion 1: Files Created (20 pts) ---
    if res_meta.get("omv_created_during_task"):
        score += 10
        feedback.append("Project file created.")
    else:
        feedback.append("Project file missing or old.")

    if res_meta.get("txt_created_during_task"):
        score += 10
        feedback.append("Results text file created.")
    else:
        feedback.append("Results text file missing or old.")

    # --- Criterion 2: Statistical Accuracy (40 pts) ---
    try:
        # Read Ground Truth
        with open(gt_local_path, 'r') as f:
            gt_lines = f.readlines()
            gt_w = float(gt_lines[0].strip())
            gt_p = float(gt_lines[1].strip())
            gt_r = float(gt_lines[2].strip())

        # Read User Output
        if os.path.exists(txt_local_path):
            with open(txt_local_path, 'r') as f:
                user_lines = f.readlines()
                if len(user_lines) >= 3:
                    user_w = float(user_lines[0].strip())
                    user_p = float(user_lines[1].strip())
                    user_r = float(user_lines[2].strip())
                    
                    # Check W (Tolerance 2%)
                    if abs(user_w - gt_w) / gt_w < 0.02:
                        score += 15
                        feedback.append(f"W statistic correct ({user_w}).")
                    else:
                        feedback.append(f"W statistic incorrect (Exp: {gt_w}, Got: {user_w}).")

                    # Check p (Tolerance 0.01)
                    if abs(user_p - gt_p) < 0.01:
                        score += 15
                        feedback.append(f"p-value correct ({user_p}).")
                    else:
                        feedback.append(f"p-value incorrect (Exp: {gt_p}, Got: {user_p}).")

                    # Check Effect Size (Tolerance 0.05)
                    if abs(user_r - gt_r) < 0.05:
                        score += 10
                        feedback.append(f"Effect size correct ({user_r}).")
                    else:
                        feedback.append(f"Effect size incorrect (Exp: {gt_r}, Got: {user_r}).")
                else:
                    feedback.append("Results file format incorrect (need 3 lines).")
        else:
            feedback.append("Results file content verification skipped (file missing).")

    except Exception as e:
        feedback.append(f"Error verifying statistics: {str(e)}")

    # --- Criterion 3: Project Integrity (10 pts) ---
    if os.path.exists(omv_local_path):
        try:
            with zipfile.ZipFile(omv_local_path, 'r') as z:
                # OMV is a zip. Check it opens.
                files = z.namelist()
                if 'Manifest.json' in files or 'metadata.json' in files or any(f.endswith('.bin') for f in files):
                    score += 10
                    feedback.append("Valid Jamovi project file.")
        except:
            feedback.append("Invalid or corrupted .omv file.")

    # --- Criterion 4: VLM Verification (30 pts) ---
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames and final:
        prompt = """
        Analyze these screenshots of Jamovi software.
        I am looking for evidence that the user performed a Wilcoxon Signed-Rank Test.
        
        Look for:
        1. A results table titled "Paired Samples T-Test".
        2. In that table, a row for "E1" vs "E2".
        3. A column or label indicating "Wilcoxon W" or "W" (NOT just Student's t).
        4. A "Descriptives" table showing Mean/Median.
        5. "Effect Size" or "Rank biserial" mentioned in the output.

        JSON Output:
        {
            "paired_test_visible": boolean,
            "wilcoxon_indicated": boolean,
            "descriptives_visible": boolean,
            "effect_size_visible": boolean,
            "variables_correct": boolean
        }
        """
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            if parsed.get("paired_test_visible"): vlm_score += 5
            if parsed.get("wilcoxon_indicated"): vlm_score += 10
            if parsed.get("descriptives_visible"): vlm_score += 5
            if parsed.get("effect_size_visible"): vlm_score += 5
            if parsed.get("variables_correct"): vlm_score += 5
            
            score += vlm_score
            feedback.append(f"VLM verified UI interaction ({vlm_score}/30 pts).")
        else:
            feedback.append("VLM verification failed to run.")

    # --- Final Result ---
    passed = score >= 70
    
    # Cleanup
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }