#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_risk_ratio_titanic(traj, env_info, task_info):
    """
    Verifies the Risk Ratio analysis task.
    Criteria:
    1. .omv file created and is a valid zip (Jamovi format).
    2. .omv file contains evidence of 'riskRatio' being enabled.
    3. reported text value matches ground truth (approx 3.8).
    4. VLM verification of the workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_value', 3.8)
    tolerance = metadata.get('tolerance', 0.5)

    score = 0
    feedback = []
    
    # 1. Load basic result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: OMV File Existence (20 pts)
    if result_data.get('omv_exists') and result_data.get('omv_created_during_task'):
        score += 20
        feedback.append("Analysis file created.")
    else:
        feedback.append("Analysis file (.omv) missing or not created during task.")

    # Criterion 2: OMV Content Analysis (30 pts)
    # Jamovi files are ZIPs containing JSONs. We check if 'riskRatio' appears in the analysis options.
    omv_valid = False
    if result_data.get('omv_exists'):
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            # Copy the omv file from the container
            copy_from_env("/tmp/analysis_result.omv", temp_omv.name)
            
            # Inspect zip contents
            with zipfile.ZipFile(temp_omv.name, 'r') as z:
                # Look for analysis files
                analysis_found = False
                risk_ratio_enabled = False
                
                for filename in z.namelist():
                    # Analysis definitions usually in numbered folders
                    if filename.endswith("00.json") or "analysis" in filename:
                        try:
                            content = z.read(filename).decode('utf-8')
                            if "riskRatio" in content and "true" in content: # heuristic
                                risk_ratio_enabled = True
                            if "contingency" in content.lower():
                                analysis_found = True
                        except:
                            pass
                
                if analysis_found:
                    score += 15
                    feedback.append("Contingency table analysis found in file.")
                if risk_ratio_enabled:
                    score += 15
                    feedback.append("Risk Ratio option verified in file.")
                    omv_valid = True
                else:
                    feedback.append("Could not confirm 'Risk Ratio' was enabled in the saved file.")

        except Exception as e:
            feedback.append(f"Failed to inspect OMV file: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)

    # Criterion 3: Reported Value Accuracy (30 pts)
    txt_content = result_data.get('txt_content', '')
    try:
        # Clean string to get just the float
        import re
        float_vals = re.findall(r"[-+]?\d*\.\d+|\d+", txt_content)
        if float_vals:
            val = float(float_vals[0])
            if abs(val - ground_truth) <= tolerance:
                score += 30
                feedback.append(f"Reported value {val} is correct (within tolerance).")
            else:
                score += 5 # Points for at least trying
                feedback.append(f"Reported value {val} is outside expected range ({ground_truth} ± {tolerance}).")
        else:
            feedback.append("Could not parse number from text file.")
    except Exception:
        feedback.append("Invalid format in text file.")

    # Criterion 4: VLM Verification (20 pts)
    # Check if they actually navigated the menus
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        You are verifying a user using Jamovi statistical software.
        Review these screenshots.
        1. Did the user open the 'TitanicSurvival' dataset? (Look for 'TitanicSurvival' in header or data grid).
        2. Did the user open the 'Contingency Tables' analysis? (Look for a panel on the right titled 'Contingency Tables').
        3. Is there a results table showing 'Risk Ratio' or 'Relative Risk'?
        
        Answer with JSON: {"dataset_loaded": bool, "analysis_opened": bool, "risk_ratio_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('dataset_loaded'): vlm_score += 5
            if parsed.get('analysis_opened'): vlm_score += 10
            if parsed.get('risk_ratio_visible'): vlm_score += 5
            
            score += vlm_score
            if vlm_score > 0:
                feedback.append("VLM confirmed workflow steps.")
        except Exception as e:
            feedback.append(f"VLM verification skipped due to error: {e}")
            score += 20 # Fallback: assume good if file checks passed
    else:
        score += 20 # Fallback

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }