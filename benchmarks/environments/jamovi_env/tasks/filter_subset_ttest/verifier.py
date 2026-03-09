#!/usr/bin/env python3
"""
Verifier for filter_subset_ttest task in Jamovi.

Verification Checks:
1. Text Result File (40 pts): Checks n, t-statistic, p-value, and means against expected values for dose=0.5.
2. OMV Project File (30 pts): Checks file structure for filter definition and t-test analysis.
3. VLM Verification (30 pts): Checks UI state via trajectory (filter bar, results panel).
4. Anti-gaming: Ensures files were created during the task window.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_filter_subset_ttest(traj, env_info, task_info):
    """
    Verify that the agent filtered the data and ran the T-Test correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values for ToothGrowth dose == 0.5
    EXPECTED_N = metadata.get('expected_n', 20)
    EXPECTED_T = metadata.get('expected_t', 3.17)
    EXPECTED_P = metadata.get('expected_p', 0.006)
    EXPECTED_MEAN_OJ = metadata.get('expected_mean_oj', 13.23)
    EXPECTED_MEAN_VC = metadata.get('expected_mean_vc', 7.98)
    
    # Tolerances
    T_TOL = metadata.get('tolerance_t', 0.5)
    P_TOL = metadata.get('tolerance_p', 0.015)
    MEAN_TOL = metadata.get('tolerance_mean', 1.0)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Fetch JSON Result Summary
    # ================================================================
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            with open(tf.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
        finally:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    # Check anti-gaming (file freshness)
    txt_fresh = task_result.get('results_txt_fresh', False)
    omv_fresh = task_result.get('omv_fresh', False)
    
    if not (txt_fresh or omv_fresh):
         return {"passed": False, "score": 0, "feedback": "No new files created during task window."}

    # ================================================================
    # 2. Verify Text Results (40 pts)
    # ================================================================
    txt_path = "/home/ga/Documents/Jamovi/filtered_ttest_results.txt"
    if task_result.get('results_txt_exists'):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tf:
                copy_from_env(txt_path, tf.name)
                parsed = {}
                with open(tf.name, 'r') as f:
                    for line in f:
                        if ':' in line:
                            key, val = line.strip().split(':', 1)
                            parsed[key.strip().lower()] = val.strip()
                os.unlink(tf.name)

            # Check N
            n_val = float(parsed.get('n_filtered', 0))
            if abs(n_val - EXPECTED_N) < 1:
                score += 10
                feedback_parts.append(f"Correct subset size (n={int(n_val)})")
            else:
                feedback_parts.append(f"Incorrect subset size (n={n_val}, expected {EXPECTED_N})")

            # Check T-statistic
            t_val = float(parsed.get('t_statistic', 0))
            if abs(abs(t_val) - abs(EXPECTED_T)) <= T_TOL:
                score += 10
                feedback_parts.append("Correct t-statistic")
            else:
                feedback_parts.append(f"Incorrect t-statistic ({t_val})")

            # Check P-value
            p_val = float(parsed.get('p_value', 1.0))
            if p_val < 0.05 and abs(p_val - EXPECTED_P) <= P_TOL:
                score += 10
                feedback_parts.append("Correct p-value")
            
            # Check Group Means
            oj_val = float(parsed.get('mean_oj', 0))
            vc_val = float(parsed.get('mean_vc', 0))
            if abs(oj_val - EXPECTED_MEAN_OJ) <= MEAN_TOL and abs(vc_val - EXPECTED_MEAN_VC) <= MEAN_TOL:
                score += 10
                feedback_parts.append("Correct group means")
            
        except Exception as e:
            feedback_parts.append(f"Error parsing text results: {str(e)}")
    else:
        feedback_parts.append("Results text file missing")

    # ================================================================
    # 3. Verify OMV Project File (30 pts)
    # ================================================================
    omv_path = "/home/ga/Documents/Jamovi/ToothGrowth_Filtered.omv"
    if task_result.get('omv_exists') and omv_fresh:
        score += 10 # Base points for saving the file
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.omv') as tf:
                copy_from_env(omv_path, tf.name)
                
                # OMV is a ZIP file
                with zipfile.ZipFile(tf.name, 'r') as z:
                    filenames = z.namelist()
                    content_str = ""
                    # Read analysis/metadata files
                    for name in filenames:
                        if name.endswith('.json') or name.endswith('.xml') or name.endswith('.yaml'):
                            try:
                                content_str += z.read(name).decode('utf-8', errors='ignore').lower()
                            except:
                                pass
                    
                    # Check for filter evidence
                    if 'filter' in content_str and ('0.5' in content_str or 'dose' in content_str):
                        score += 10
                        feedback_parts.append("Filter found in project file")
                    
                    # Check for T-Test evidence
                    if 'ttest' in content_str or 'independent' in content_str:
                        score += 10
                        feedback_parts.append("T-Test analysis found in project file")
                
                os.unlink(tf.name)
        except Exception as e:
            feedback_parts.append(f"Error inspecting OMV file: {str(e)}")
    else:
        feedback_parts.append("OMV project file missing or not saved")

    # ================================================================
    # 4. VLM Verification (30 pts)
    # ================================================================
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    if all_frames:
        prompt = """
        You are verifying a Jamovi statistics task. 
        Goal: Filter data (dose=0.5) and run Independent Samples T-Test.
        
        Look at the images and answer:
        1. Is the Jamovi application visible?
        2. Is there a filter bar/row visible at the top of the data grid (often showing a formula or funnel icon)?
        3. Is there a results panel showing T-Test tables (Independent Samples T-Test)?
        4. Do the results show 'Group Descriptives' or mean/SD tables?
        
        Return JSON:
        {"jamovi_visible": bool, "filter_visible": bool, "ttest_visible": bool, "descriptives_visible": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=all_frames)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('jamovi_visible'):
                if parsed.get('filter_visible'):
                    score += 10
                    feedback_parts.append("VLM: Filter usage detected")
                if parsed.get('ttest_visible'):
                    score += 10
                    feedback_parts.append("VLM: T-Test results detected")
                if parsed.get('descriptives_visible'):
                    score += 10
                    feedback_parts.append("VLM: Descriptives table detected")
        else:
            feedback_parts.append("VLM verification failed")
            # Fallback: if programmatic score is high, assume VLM might have missed it but work was done
            if score >= 60:
                score += 15
                feedback_parts.append("Fallback VLM points awarded based on strong programmatic evidence")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 50 and (task_result.get('results_txt_exists') or task_result.get('omv_exists'))
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }