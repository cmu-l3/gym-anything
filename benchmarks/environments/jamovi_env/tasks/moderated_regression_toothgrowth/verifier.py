#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_moderated_regression(traj, env_info, task_info):
    """
    Verifies the moderated regression task in Jamovi.
    
    Criteria:
    1. Output OMV file exists and was created during the task.
    2. Results text file exists and contains values matching the ground truth:
       - R-squared (~0.73)
       - F-statistic (~50.4)
       - Interaction estimate (~3.9)
       - Interaction p-value (~0.024)
    3. VLM verification of the final screenshot or trajectory frames to confirm
       the interaction term is visible in the UI.
    """
    
    # 1. Setup and Helper Functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {
        "r_squared": 0.7296,
        "f_statistic": 50.36,
        "interaction_estimate": 3.904,
        "interaction_p": 0.024
    })
    tolerances = metadata.get('tolerances', {
        "r_squared": 0.02,
        "f_statistic": 2.0,
        "estimate": 0.5,
        "p_value": 0.01
    })

    score = 0
    feedback_log = []
    
    # 2. Retrieve Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Check OMV File (10 pts)
    if task_result.get('omv_exists') and task_result.get('omv_created_during_task'):
        score += 10
        feedback_log.append("Project file (.omv) saved successfully.")
    elif task_result.get('omv_exists'):
        score += 5
        feedback_log.append("Project file exists but timestamp suggests it wasn't created during this session.")
    else:
        feedback_log.append("Project file (.omv) missing.")

    # 4. Check Text File Existence (5 pts)
    txt_content = ""
    if task_result.get('txt_exists') and task_result.get('txt_created_during_task'):
        score += 5
        feedback_log.append("Results text file created.")
        
        # Retrieve content for analysis
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(task_result['txt_path'], temp_txt.name)
            with open(temp_txt.name, 'r', errors='ignore') as f:
                txt_content = f.read()
        except Exception as e:
            feedback_log.append(f"Could not read text file content: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback_log.append("Results text file missing.")

    # 5. Verify Numerical Values in Text File (75 pts)
    # We look for numbers near keywords using regex
    
    def extract_value(text, keywords):
        # Look for patterns like "R-squared: 0.73" or "R^2 = 0.73"
        # Regex matches: keyword followed by optional colon/equals, optional whitespace, then a number
        for kw in keywords:
            pattern = re.compile(re.escape(kw) + r"[:=\s]+(-?\d+\.?\d*)", re.IGNORECASE)
            match = pattern.search(text)
            if match:
                try:
                    return float(match.group(1))
                except ValueError:
                    continue
        return None

    # Verify R-squared (15 pts)
    r2_val = extract_value(txt_content, ["R-squared", "R^2", "R2", "R squared"])
    if r2_val is not None:
        if abs(r2_val - ground_truth['r_squared']) <= tolerances['r_squared']:
            score += 15
            feedback_log.append(f"R-squared correct ({r2_val}).")
        else:
            feedback_log.append(f"R-squared incorrect (Found {r2_val}, expected ~{ground_truth['r_squared']}).")
    else:
        feedback_log.append("R-squared value not found in text.")

    # Verify F-statistic (15 pts)
    f_val = extract_value(txt_content, ["F-statistic", "F statistic", "F-test", "F value", "F"])
    if f_val is not None:
        if abs(f_val - ground_truth['f_statistic']) <= tolerances['f_statistic']:
            score += 15
            feedback_log.append(f"F-statistic correct ({f_val}).")
        else:
            feedback_log.append(f"F-statistic incorrect (Found {f_val}, expected ~{ground_truth['f_statistic']}).")
    else:
        feedback_log.append("F-statistic not found in text.")

    # Verify Overall p-value (10 pts)
    p_val = extract_value(txt_content, ["Overall p-value", "p-value", "Model p", "p"])
    # Note: Regex might grab the first 'p-value' it sees. 
    # If the user listed interaction p-value first, this might be tricky.
    # However, standard reporting usually puts model fit first.
    if p_val is not None:
        if p_val < 0.01: # Expected is < 0.001
            score += 10
            feedback_log.append(f"Overall p-value correct ({p_val}).")
        else:
            feedback_log.append(f"Overall p-value incorrect (Found {p_val}, expected < 0.001).")
    else:
        # Check for "< .001" notation which extract_value might miss
        if "<" in txt_content and (".001" in txt_content or "0.001" in txt_content):
            score += 10
            feedback_log.append("Overall p-value correct (< .001 detected).")
        else:
            feedback_log.append("Overall p-value not found.")

    # Verify Interaction Estimate (20 pts)
    # This is the specific check for the interaction term
    # Look for "Interaction" or "dose*supp" or "dose:supp"
    int_est = extract_value(txt_content, ["Interaction estimate", "Interaction coeff", "dose*supp", "dose:supp", "dose x supp"])
    if int_est is not None:
        if abs(int_est - ground_truth['interaction_estimate']) <= tolerances['estimate']:
            score += 20
            feedback_log.append(f"Interaction estimate correct ({int_est}).")
        else:
            feedback_log.append(f"Interaction estimate incorrect (Found {int_est}, expected ~{ground_truth['interaction_estimate']}).")
    else:
        feedback_log.append("Interaction estimate not found.")

    # Verify Interaction p-value (15 pts)
    # Harder to regex distinct from overall p without context, but we try specific keywords
    int_p = extract_value(txt_content, ["Interaction p-value", "Interaction p", "dose*supp p", "dose:supp p"])
    if int_p is not None:
        if abs(int_p - ground_truth['interaction_p']) <= tolerances['p_value']:
            score += 15
            feedback_log.append(f"Interaction p-value correct ({int_p}).")
        else:
            feedback_log.append(f"Interaction p-value incorrect (Found {int_p}, expected ~{ground_truth['interaction_p']}).")
    else:
        feedback_log.append("Interaction p-value not found.")

    # 6. VLM Verification (10 pts)
    # Only if score is high enough to matter, or as a safety check
    vlm_score = 0
    if score >= 40: # Only bother with VLM if they did some work
        from gym_anything.vlm import get_final_screenshot, query_vlm
        
        final_screenshot = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a statistical analysis task in Jamovi.
        The user should have run a Linear Regression with an interaction term.
        
        Look at the screenshot and check for:
        1. A "Linear Regression" results table.
        2. A "Model Coefficients" table.
        3. An interaction term in the coefficients table. It usually looks like "dose ✻ supp", "dose * supp", or "dose:supp".
        
        Answer JSON:
        {
            "regression_table_visible": true/false,
            "interaction_term_visible": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        try:
            result = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = result.get('parsed', {})
            
            if parsed.get('regression_table_visible', False):
                vlm_score += 5
                
            if parsed.get('interaction_term_visible', False):
                vlm_score += 5
                feedback_log.append("VLM confirmed visible interaction term.")
            else:
                feedback_log.append("VLM did not clearly see the interaction term.")
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: give points if text analysis was very strong (anti-frustration)
            if score >= 80:
                vlm_score = 10

    score += vlm_score

    # Cap score
    score = min(score, 100)
    
    # 7. Final Determination
    # Pass if score >= 60 AND (Interaction Estimate was found OR Interaction P-value was found)
    # This ensures they actually ran the interaction model, not just a simple additive model
    interaction_verified = (int_est is not None and abs(int_est - ground_truth['interaction_estimate']) <= tolerances['estimate']) or \
                           (int_p is not None and abs(int_p - ground_truth['interaction_p']) <= tolerances['p_value']) or \
                           (vlm_score >= 10) # VLM saw it
                           
    passed = (score >= 60) and interaction_verified
    
    if score >= 60 and not interaction_verified:
        feedback_log.append("FAILED: Score is high but interaction term verification failed. Did you run the interaction model?")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }