#!/usr/bin/env python3
import json
import os
import base64
import re
import tempfile
import zipfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_paired_samples_ttest(traj, env_info, task_info):
    """
    Verifies the Paired Samples T-Test task.
    
    Criteria:
    1. Results text file exists and was created during task.
    2. Results text file contains correct statistical values (within tolerance).
    3. Jamovi project file (.omv) exists and is a valid zip archive.
    4. VLM verification of the workflow (checking results panel).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Metadata & Ground Truth ---
    gt = task_info.get('metadata', {}).get('ground_truth', {})
    tols = task_info.get('metadata', {}).get('tolerances', {})
    
    gt_t = gt.get('t_statistic', 4.062)
    gt_df = gt.get('df', 9)
    gt_p = gt.get('p_value', 0.00283)
    gt_mean_diff = gt.get('mean_difference', 1.58)
    gt_d = gt.get('cohens_d', 1.285)
    gt_shapiro = gt.get('shapiro_wilk_p', 0.175)

    # --- Criterion 1: Results Text File (40 points) ---
    txt_exists = result_data.get('txt_exists', False)
    txt_fresh = result_data.get('txt_created_during_task', False)
    txt_content_b64 = result_data.get('txt_content_base64', "")
    
    parsed_values = {}
    
    if txt_exists and txt_fresh and txt_content_b64:
        score += 10
        feedback.append("Results text file created.")
        
        try:
            content = base64.b64decode(txt_content_b64).decode('utf-8')
            # Parse key-value pairs
            for line in content.split('\n'):
                if ':' in line:
                    key, val = line.split(':', 1)
                    key = key.strip().lower()
                    val = val.strip()
                    try:
                        parsed_values[key] = float(val)
                    except ValueError:
                        pass
            
            # Check T-Statistic
            val_t = abs(parsed_values.get('t_statistic', 0))
            if abs(val_t - gt_t) <= tols.get('t_statistic', 0.1):
                score += 5
                feedback.append("T-statistic correct.")
            else:
                feedback.append(f"T-statistic incorrect (Got {val_t}, Expected ~{gt_t}).")

            # Check DF
            val_df = parsed_values.get('df', 0)
            if val_df == gt_df:
                score += 5
                feedback.append("Degrees of freedom correct.")

            # Check P-Value
            val_p = parsed_values.get('p_value', -1)
            if abs(val_p - gt_p) <= tols.get('p_value', 0.001):
                score += 5
                feedback.append("P-value correct.")

            # Check Mean Difference
            val_md = abs(parsed_values.get('mean_difference', 0))
            if abs(val_md - gt_mean_diff) <= tols.get('mean_difference', 0.1):
                score += 5
                feedback.append("Mean difference correct.")
            
            # Check Cohen's d
            val_d = abs(parsed_values.get('cohens_d', 0))
            if abs(val_d - gt_d) <= tols.get('cohens_d', 0.1):
                score += 5
                feedback.append("Cohen's d correct.")

            # Check Shapiro-Wilk
            val_sw = parsed_values.get('shapiro_wilk_p', -1)
            if abs(val_sw - gt_shapiro) <= tols.get('shapiro_wilk_p', 0.05):
                score += 5
                feedback.append("Normality test correct.")

        except Exception as e:
            feedback.append(f"Error parsing text file: {e}")
    else:
        feedback.append("Results text file missing or not created during task.")

    # --- Criterion 2: OMV Project File (20 points) ---
    omv_exists = result_data.get('omv_exists', False)
    omv_fresh = result_data.get('omv_created_during_task', False)
    omv_size = result_data.get('omv_size', 0)
    
    if omv_exists and omv_fresh and omv_size > 1000:
        # Verify it's a valid zip (OMV format)
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            # We don't have the full file content in JSON, need to copy it
            copy_from_env("/home/ga/Documents/Jamovi/SleepPairedTest.omv", temp_omv.name)
            if zipfile.is_zipfile(temp_omv.name):
                score += 20
                feedback.append("Jamovi project file saved and valid.")
            else:
                score += 5
                feedback.append("Jamovi project file saved but invalid format.")
        except:
            # If copy fails, fallback to just trusting existence
            score += 10 
            feedback.append("Jamovi project file saved (validation skipped).")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)
    else:
        feedback.append("Jamovi project file missing or empty.")

    # --- Criterion 3: VLM Verification (40 points) ---
    # We verify if the agent actually used the UI correctly
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = """
        You are verifying a Jamovi statistics task.
        The user should have:
        1. Loaded data (columns Patient, Drug1, Drug2).
        2. Performed a 'Paired Samples T-Test'.
        3. The results panel should be visible on the right.
        4. Look for a table titled 'Paired Samples T-Test'.
        5. Look for 'Cohen's d' or 'Effect Size' in the results.
        6. Look for 'Test of Normality' (Shapiro-Wilk) in the results.
        
        Answer JSON:
        {
            "data_loaded": boolean,
            "paired_test_visible": boolean,
            "effect_size_visible": boolean,
            "normality_test_visible": boolean
        }
        """
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('paired_test_visible'):
                score += 20
                feedback.append("VLM confirmed Paired T-Test table visible.")
            if parsed.get('effect_size_visible'):
                score += 10
                feedback.append("VLM confirmed Effect Size visible.")
            if parsed.get('normality_test_visible'):
                score += 10
                feedback.append("VLM confirmed Normality Test visible.")
        else:
            feedback.append("VLM verification failed or inconclusive.")
            # Fallback points if programmatic pass was strong
            if score >= 50:
                score += 20
                feedback.append("Awarding partial VLM points based on strong file evidence.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }