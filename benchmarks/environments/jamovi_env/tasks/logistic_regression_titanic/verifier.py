#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import base64
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_logistic_regression_titanic(traj, env_info, task_info):
    """
    Verifies the Titanic Logistic Regression task.
    
    Criteria:
    1. .omv file exists, is a valid zip, and created during task.
    2. Report file exists and contains correct statistical values.
    3. VLM verification of the workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    score = 0
    feedback = []
    
    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify .omv file (Project File)
    omv_exists = result.get("omv_exists", False)
    omv_fresh = result.get("omv_created_during_task", False)
    
    if omv_exists and omv_fresh:
        score += 10
        feedback.append(".omv project file created.")
        
        # Verify it's a valid OMV (ZIP) file
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env(result["omv_path"], temp_omv.name)
            if zipfile.is_zipfile(temp_omv.name):
                score += 10
                feedback.append(".omv file is a valid archive.")
                # Bonus: Check if it contains analysis metadata (optional depth)
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    filenames = z.namelist()
                    if any('analysis' in f for f in filenames) or 'index.json' in filenames:
                        score += 5
                        feedback.append("Project file contains analysis data.")
            else:
                feedback.append("ERROR: .omv file is not a valid zip archive.")
        except Exception:
            feedback.append("Warning: Could not inspect .omv file content.")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)
    else:
        feedback.append("Missing or stale .omv project file.")

    # 3. Verify Report Content (Statistical Accuracy)
    report_exists = result.get("report_exists", False)
    if report_exists:
        score += 10
        content_b64 = result.get("report_content_b64", "")
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore').lower()
            
            # Ground Truth Ranges
            # Model p < 0.001
            p_val_match = re.search(r'p[:\s]*[<]?\s*(\.?[0-9]+)', content)
            if p_val_match or "p < .001" in content or "p < 0.001" in content:
                score += 10
                feedback.append("Model p-value reported correctly.")
            
            # Sex (Male) Odds Ratio: Expected ~0.08 (Range 0.04 - 0.20)
            sex_match = re.search(r'sex.*ratio[:\s]*(\.?[0-9]+)', content)
            if sex_match:
                val = float(sex_match.group(1))
                if 0.04 <= val <= 0.20:
                    score += 15
                    feedback.append(f"Sex odds ratio correct ({val}).")
                else:
                    feedback.append(f"Sex odds ratio out of range ({val}).")
            else:
                feedback.append("Could not find Sex odds ratio.")

            # Age Odds Ratio: Expected ~0.96 (Range 0.90 - 1.00)
            age_match = re.search(r'age.*ratio[:\s]*(\.?[0-9]+)', content)
            if age_match:
                val = float(age_match.group(1))
                if 0.90 <= val <= 1.00:
                    score += 15
                    feedback.append(f"Age odds ratio correct ({val}).")
                else:
                    feedback.append(f"Age odds ratio out of range ({val}).")
            else:
                feedback.append("Could not find Age odds ratio.")

            # Significance checks
            if "sex significant: yes" in content: score += 5
            if "age significant: yes" in content: score += 5
            if "passengerclass significant: yes" in content: score += 5

        except Exception as e:
            feedback.append(f"Error parsing report: {str(e)}")
    else:
        feedback.append("Report file not found.")

    # 4. VLM Verification (Trajectory)
    # Check if they actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        all_images = frames + [final_img] if final_img else frames
        
        prompt = """
        Review these screenshots of a user using Jamovi.
        1. Is the Titanic dataset loaded (columns like 'survived', 'sex', 'age', 'pclass')?
        2. Is the 'Logistic Regression' or 'Binomial' analysis panel open?
        3. Is there a results table showing 'Odds Ratio' or 'Odds Ratio (95% CI)'?
        
        Answer with JSON: {"dataset_loaded": bool, "regression_run": bool, "odds_ratio_visible": bool}
        """
        
        vlm_res = query_vlm(images=all_images, prompt=prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("dataset_loaded"): score += 5
            if parsed.get("regression_run"): score += 5
            if parsed.get("odds_ratio_visible"): 
                score += 5
                feedback.append("VLM confirmed Odds Ratio table visible.")
    except Exception as e:
        feedback.append(f"VLM check skipped: {str(e)}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }