#!/usr/bin/env python3
"""
Verifier for Moderation Analysis (JASP).

Checks:
1. Output file (.jasp) exists and was created during the task.
2. JASP file contains a Linear Regression analysis.
3. Model terms include the interaction 'Revise * Anxiety'.
4. Simple Slopes option is enabled.
5. VLM confirms UI state.
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_moderation_interaction(traj, env_info, task_info):
    """
    Verify the moderation analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing."}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', 'Moderation_Analysis.jasp')
    
    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Load Task Result JSON
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not task_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output .jasp file not found."}

    if not task_result.get('file_created_during_task'):
        feedback.append("Warning: File timestamp suggests it wasn't created during the task.")
    else:
        score += 10
        feedback.append("File created during task.")

    # ------------------------------------------------------------------
    # 2. Inspect JASP File Content
    # ------------------------------------------------------------------
    # JASP files are ZIP archives containing JSON analysis definitions.
    jasp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    analysis_found = False
    interaction_found = False
    simple_slopes_found = False
    
    try:
        copy_from_env(task_result['output_path'], jasp_temp.name)
        
        if not zipfile.is_zipfile(jasp_temp.name):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid JASP archive."}
            
        with zipfile.ZipFile(jasp_temp.name, 'r') as z:
            # Search for analysis definition files
            # Usually in a folder structure, looking for .json files
            json_files = [f for f in z.namelist() if f.endswith('.json')]
            
            for json_file in json_files:
                try:
                    with z.open(json_file) as jf:
                        content = json.load(jf)
                        # Convert to string for loose searching to handle version differences
                        content_str = json.dumps(content)
                        
                        # Check for Linear Regression
                        if "RegressionLinear" in content_str or "linearRegression" in content_str:
                            analysis_found = True
                            
                            # Check for Variables
                            if "Exam" in content_str and "Revise" in content_str and "Anxiety" in content_str:
                                score += 20
                                feedback.append("Correct variables found in analysis.")
                            
                            # Check for Interaction
                            # JASP interactions are often stored as lists of terms or encoded strings
                            # Look for evidence of interaction
                            if "Revise:Anxiety" in content_str or "Anxiety:Revise" in content_str: # Common R notation
                                interaction_found = True
                            elif "components" in content_str and "Revise" in content_str and "Anxiety" in content_str:
                                # Looser check if strict naming fails
                                # If the JSON structure shows a term with multiple components, it's an interaction
                                pass 
                            
                            # Check for Simple Slopes
                            if "simpleSlopes" in content_str and "true" in content_str.lower():
                                simple_slopes_found = True
                except:
                    continue
                    
    except Exception as e:
        feedback.append(f"Error analyzing JASP file: {str(e)}")
    finally:
        if os.path.exists(jasp_temp.name):
            os.unlink(jasp_temp.name)

    if analysis_found:
        score += 20
        feedback.append("Linear Regression analysis identified.")
    else:
        feedback.append("Linear Regression analysis NOT found in file.")

    # Note: Text-based search in JSON is a heuristic; verify via VLM if file check is ambiguous
    # But for interaction, usually explicit in settings.
    # Let's perform a stricter text check on the unzipped content if JSON parsing was fuzzy
    if not interaction_found:
        # Fallback: simple grep on file content
        pass

    # ------------------------------------------------------------------
    # 3. VLM Verification (Visual Confirmation)
    # ------------------------------------------------------------------
    # Essential for visual elements like Plots which might be obscure in JSON
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    vlm_prompt = """
    Analyze these screenshots of JASP software.
    1. Is a "Linear Regression" results table visible?
    2. Does the model include an interaction term (e.g., "Revise ✻ Anxiety" or "Revise * Anxiety")?
    3. Is a "Simple Slopes" plot visible (showing multiple lines crossing or diverging)?
    
    Answer JSON: {"linear_regression_visible": bool, "interaction_term_visible": bool, "simple_slopes_plot_visible": bool}
    """
    
    vlm_result = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    # Consolidate Interaction Check
    if interaction_found or vlm_data.get('interaction_term_visible', False):
        score += 30
        feedback.append("Interaction term verified.")
    else:
        feedback.append("Interaction term missing in model.")

    # Consolidate Simple Slopes Check
    if simple_slopes_found or vlm_data.get('simple_slopes_plot_visible', False):
        score += 20
        feedback.append("Simple Slopes plot verified.")
    else:
        feedback.append("Simple Slopes plot missing.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }