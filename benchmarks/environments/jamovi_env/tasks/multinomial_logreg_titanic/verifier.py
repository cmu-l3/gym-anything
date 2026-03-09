#!/usr/bin/env python3
"""
Verifier for multinomial_logreg_titanic task.

Checks:
1. .omv file creation and validity (zip archive).
2. Analysis configuration inside .omv (Dependent, Factors, Covariates).
3. Specific options enabled (Model Fit, Odds Ratio).
4. VLM verification of the workflow.
"""

import json
import tempfile
import os
import zipfile
import logging
import sys

# Import VLM utils from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multinomial_logreg_titanic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get result JSON from container
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check file existence and timestamp
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output .omv file not found"}
    
    score += 10 # File exists
    
    if task_result.get('file_created_during_task', False):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-dates task)")

    # 3. Analyze .omv file content
    output_path = task_result.get('output_path')
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .omv is a zip
    
    analysis_correct = False
    details = {}
    
    try:
        copy_from_env(output_path, temp_omv.name)
        
        with zipfile.ZipFile(temp_omv.name, 'r') as z:
            # Extract all JSONs to find the analysis definition
            json_files = [f for f in z.namelist() if f.endswith('.json')]
            
            found_analysis = False
            for jf in json_files:
                try:
                    content = json.loads(z.read(jf).decode('utf-8'))
                except:
                    continue
                
                # Check for analysis type
                # Structure varies, but usually has 'analysisType' or is in a list of analyses
                # We search recursively or check top level keys
                
                # Helper to flatten/search dictionary
                content_str = json.dumps(content).lower()
                
                if 'logregmulti' in content_str: # Correct analysis type
                    found_analysis = True
                    score += 20
                    feedback_parts.append("Multinomial Regression found")
                    
                    # Parse specific options if possible
                    # Jamovi .omv JSON structure is complex, often under 'options'
                    # We will do a robust string search in the JSON content for this specific analysis file
                    
                    # Check Dependent Variable
                    if 'passengerclass' in content_str:
                        score += 15
                        details['dep_var'] = True
                    else:
                        details['dep_var'] = False
                        
                    # Check Factors
                    if 'survived' in content_str and 'sex' in content_str:
                        score += 15
                        details['factors'] = True
                    else:
                        details['factors'] = False
                        
                    # Check Covariates
                    if 'age' in content_str:
                        score += 10
                        details['covariates'] = True
                    else:
                        details['covariates'] = False
                        
                    # Check Options: Model Fit (Pseudo R2, etc)
                    # Keys often like "pseudoR2", "modelTest"
                    if '"pseudor2":true' in content_str.replace(" ", "") or '"modeltest":true' in content_str.replace(" ", ""):
                        score += 8
                        details['model_fit'] = True
                        feedback_parts.append("Model Fit enabled")
                    
                    # Check Options: Odds Ratio
                    # Keys like "oddsRatio", "OR", "expCoef"
                    if '"oddsratio":true' in content_str.replace(" ", "") or '"or":true' in content_str.replace(" ", ""):
                        score += 7
                        details['odds_ratio'] = True
                        feedback_parts.append("Odds Ratio enabled")
                    
                    analysis_correct = True
                    break
            
            if not found_analysis:
                feedback_parts.append("Correct analysis type (Multinomial) not found in file")
                
    except Exception as e:
        feedback_parts.append(f"Failed to parse .omv file: {str(e)}")
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    # 4. VLM Verification (Trajectory based)
    # This verifies the agent actually interacted with the UI, especially if the file parsing is ambiguous
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if frames:
        # We need to call the VLM
        # Note: In a real environment, we would import `query_vlm`.
        # Here we assume the framework handles it or we mock it if running locally without GPU.
        try:
            from gym_anything.vlm import query_vlm
            
            prompt = """
            Review these screenshots of a user using Jamovi statistical software.
            The user should be performing a Multinomial Logistic Regression on the Titanic dataset.
            
            Look for:
            1. The 'Logistic Regression' menu or 'N Outcomes' option being selected.
            2. The 'Multinomial Logistic Regression' analysis panel open.
            3. 'passengerClass' being moved to Dependent Variable.
            4. 'survived' and 'sex' in Factors.
            5. 'age' in Covariates.
            6. A results table showing 'Multinomial Logistic Regression' coefficients.
            
            Does the user appear to have successfully set up this specific analysis?
            Return JSON: {"success": boolean, "confidence": float 0-1}
            """
            
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result.get('parsed', {}).get('success', False):
                score += 10
                feedback_parts.append("VLM verified workflow")
            
        except ImportError:
            # Fallback if VLM not available in verifier env (score conservatively)
            # If we already passed file checks, we assume UI was used.
            if analysis_correct:
                score += 10
                feedback_parts.append("VLM skipped (file verified)")

    # 5. Final Scoring
    passed = score >= 65 and analysis_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts),
        "details": details
    }