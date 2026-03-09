#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import shutil
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_factorial_anova(traj, env_info, task_info):
    """
    Verifies the Factorial ANOVA task using file inspection and VLM.
    
    Strategy:
    1. File Check: Verify .jasp file exists and was created during the task.
    2. Content Check: Unzip .jasp and search JSON configs for 'anova', 'len', 'supp', 'dose', and interactions.
    3. Visual Check: Use VLM to look for the ANOVA table and Interaction Plot in the final screenshot.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path')
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # PART 1: Metadata & File Existence (20 points)
    # =========================================================
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)
            
    if not result_meta.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output .jasp file not found. Did you save the analysis?"
        }
        
    score += 10 # File exists
    
    if result_meta.get('file_created_during_task'):
        score += 10 # Anti-gaming: File created during session
    else:
        feedback_parts.append("Warning: Output file timestamp is older than task start.")

    # =========================================================
    # PART 2: JASP File Content Analysis (40 points)
    # =========================================================
    # JASP files are ZIP archives containing JSON definitions of the analysis.
    # We will search the JSONs for key configuration strings.
    
    jasp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    analysis_found = False
    interaction_found = False
    plots_found = False
    
    try:
        copy_from_env(expected_path, jasp_temp.name)
        
        if zipfile.is_zipfile(jasp_temp.name):
            with zipfile.ZipFile(jasp_temp.name, 'r') as z:
                # Iterate through all files in the zip to find analysis configurations
                # Typically inside 'analysis' folders or 'index.json'
                all_text_content = ""
                for filename in z.namelist():
                    if filename.endswith('.json') or filename.endswith('.qml'):
                        try:
                            with z.open(filename) as f:
                                content = f.read().decode('utf-8', errors='ignore')
                                all_text_content += content + "\n"
                        except:
                            continue
                
                # Loose keyword matching in the configuration dump
                # 1. Check for ANOVA
                if '"analysisName":"ANOVA"' in all_text_content or 'jaspAnova' in all_text_content:
                    score += 10
                    analysis_found = True
                    feedback_parts.append("ANOVA analysis detected in file.")
                
                # 2. Check variables (Dependent: len, Fixed: supp, dose)
                # JASP JSONs often store variables as lists
                if '"len"' in all_text_content and '"supp"' in all_text_content and '"dose"' in all_text_content:
                    score += 10
                    feedback_parts.append("Correct variables found in configuration.")
                
                # 3. Check for Interaction
                # Interactions often denoted by combining names or specific model terms
                if 'supp' in all_text_content and 'dose' in all_text_content and 'modelTerms' in all_text_content:
                    # Heuristic: if model terms are present and both vars are there, interaction is likely default
                    score += 10
                    interaction_found = True
                    feedback_parts.append("Model terms configuration found.")
                
                # 4. Check for Plots/Descriptives
                if 'descriptives' in all_text_content.lower() or 'plot' in all_text_content.lower():
                    score += 10
                    plots_found = True
                    feedback_parts.append("Descriptives/Plots configuration detected.")

        else:
            feedback_parts.append("Output file is not a valid ZIP/JASP archive.")
            
    except Exception as e:
        feedback_parts.append(f"Error inspecting JASP file content: {e}")
    finally:
        if os.path.exists(jasp_temp.name):
            os.unlink(jasp_temp.name)

    # =========================================================
    # PART 3: VLM Visual Verification (40 points)
    # =========================================================
    # We use the final screenshot to confirm the UI shows the correct results table.
    # This acts as a ground truth check against the file content heuristics.
    
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a JASP statistical analysis task.
    The user was asked to perform a Factorial ANOVA with an Interaction effect.
    
    Look at the screenshot and check for:
    1. A "Results" panel is visible.
    2. An "ANOVA" table is visible.
    3. The ANOVA table lists "supp", "dose", and the interaction "supp ✻ dose" (or "supp * dose").
    4. A plot is visible showing lines (Interaction Plot).
    5. A "Post Hoc Comparisons" table is visible.
    
    Return JSON:
    {
        "anova_table_visible": boolean,
        "interaction_term_visible": boolean,
        "plot_visible": boolean,
        "post_hoc_visible": boolean,
        "feedback": string
    }
    """
    
    vlm_result = query_vlm(
        images=[final_screenshot], 
        prompt=vlm_prompt
    )
    
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('anova_table_visible'):
        score += 10
        feedback_parts.append("VLM: ANOVA table visible.")
    
    if vlm_data.get('interaction_term_visible'):
        score += 10
        feedback_parts.append("VLM: Interaction term 'supp * dose' visible in results.")
    else:
        feedback_parts.append("VLM: Interaction term NOT clearly visible.")
        
    if vlm_data.get('plot_visible'):
        score += 10
        feedback_parts.append("VLM: Descriptive/Interaction plot visible.")
        
    if vlm_data.get('post_hoc_visible'):
        score += 10
        feedback_parts.append("VLM: Post Hoc table visible.")

    # =========================================================
    # Final Scoring
    # =========================================================
    
    # Calculate Pass/Fail
    # Threshold: 70 points
    # Must have file existence + basic analysis detection
    
    passed = score >= 70
    
    if passed:
        feedback_parts.insert(0, "Task Passed!")
    else:
        feedback_parts.insert(0, "Task Failed.")
        
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }