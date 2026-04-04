#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_partial_correlation(traj, env_info, task_info):
    """
    Verifies that the agent performed a Partial Correlation analysis.
    
    Verification steps:
    1. Check if .jasp file exists and was created during task.
    2. Unzip .jasp file and inspect JSON analysis specification.
    3. Confirm 'Exam' and 'Anxiety' are variables.
    4. Confirm 'Revise' is the conditioning variable.
    5. Confirm Plots/CI enabled.
    6. VLM trajectory verification as backup.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    metadata = task_info.get('metadata', {})
    
    # Score components
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch Result Metadata
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file PartialCorrelation_Exam.jasp not found."}
    
    score += 10 # File exists
    feedback_parts.append("File created")
    
    if created_during:
        score += 10
        feedback_parts.append("New file generated")
    else:
        feedback_parts.append("File timestamp suspiciously old")

    # ---------------------------------------------------------
    # 2. Analyze JASP File Content
    # ---------------------------------------------------------
    jasp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    analysis_found = False
    config_correct = False
    control_var_correct = False
    
    try:
        copy_from_env("/tmp/verification_output.jasp", jasp_temp.name)
        
        with zipfile.ZipFile(jasp_temp.name, 'r') as z:
            # JASP files usually have an 'embedded' folder containing the analyses
            # or an index.html and json files. We look for any JSON that looks like analysis config.
            # Common path: index.html linking to data, but specifications are often in 'results' or 'state' JSONs.
            # We will scan all .json files in the zip.
            
            for filename in z.namelist():
                if filename.endswith('.json'):
                    try:
                        with z.open(filename) as f:
                            content = json.load(f)
                            # Deep search for Correlation analysis
                            # JASP JSON structure is complex. We look for signatures.
                            # Signature for Correlation: "title": "Correlation" or similar
                            # The structure usually has a "results" array or "analyses" array.
                            
                            def search_json(obj):
                                nonlocal analysis_found, config_correct, control_var_correct, score
                                if isinstance(obj, dict):
                                    # Check if this object describes a Correlation analysis
                                    title = obj.get('title', '')
                                    results_title = obj.get('results', {}).get('title', '')
                                    
                                    # Identify Correlation Analysis
                                    if 'Correlation' in title or 'Correlation' in results_title or obj.get('name') == 'Correlation':
                                        analysis_found = True
                                        
                                        # Check variables in "options" or similar fields
                                        options = obj.get('options', {})
                                        
                                        # Variables check
                                        # JASP internal keys: 'variables', 'conditioning'
                                        vars_list = options.get('variables', [])
                                        cond_list = options.get('conditioning', [])
                                        
                                        # Robustness: sometimes keys differ by version
                                        if not vars_list and 'variables' in obj:
                                            vars_list = obj['variables']
                                        
                                        # Check main variables
                                        if 'Exam' in str(vars_list) and 'Anxiety' in str(vars_list):
                                            if "Main variables correct" not in feedback_parts:
                                                score += 20
                                                feedback_parts.append("Main variables correct")
                                                config_correct = True
                                        
                                        # Check Conditioning Variable (The critical part)
                                        if 'Revise' in str(cond_list):
                                            if "Control variable correct" not in feedback_parts:
                                                score += 30
                                                feedback_parts.append("Control variable correct")
                                                control_var_correct = True
                                        
                                        # Check settings
                                        if options.get('confidenceIntervals') is True:
                                            if "CI enabled" not in feedback_parts:
                                                score += 10
                                                feedback_parts.append("CI enabled")
                                        
                                        if options.get('plots') is True or options.get('plotScatter') is True:
                                            if "Plots enabled" not in feedback_parts:
                                                score += 10
                                                feedback_parts.append("Plots enabled")
                                    
                                    for k, v in obj.items():
                                        search_json(v)
                                elif isinstance(obj, list):
                                    for item in obj:
                                        search_json(item)

                            search_json(content)
                    except Exception as e:
                        logger.warning(f"Error parsing JSON {filename}: {e}")
                        continue
                        
    except Exception as e:
        feedback_parts.append(f"Analysis file corrupt or unreadable: {e}")
    finally:
        if os.path.exists(jasp_temp.name):
            os.unlink(jasp_temp.name)

    if not analysis_found:
        feedback_parts.append("No Correlation analysis found in file")

    # ---------------------------------------------------------
    # 3. VLM Verification (Backup/Confirmation)
    # ---------------------------------------------------------
    # If programmatic check passed perfectly, VLM is just a bonus check.
    # If programmatic check failed (e.g. file format changed), VLM can save the day partially.
    
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames:
        images = frames + ([final] if final else [])
        prompt = """
        Review these screenshots of a user using JASP statistical software.
        
        Goal: Run a Partial Correlation between 'Exam' and 'Anxiety' controlling for 'Revise'.
        
        Look for:
        1. The 'Correlation' module being open.
        2. 'Exam' and 'Anxiety' in the main variables box.
        3. 'Revise' in the 'Conditioned on' or 'Partial' variables box (this is CRITICAL).
        4. A scatter plot or correlation matrix in the results panel on the right.
        
        Return JSON: {"analysis_visible": bool, "conditioning_visible": bool, "scatter_plot_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(images=images, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            # If programmatic check missed (maybe due to JASP version json diffs), but VLM sees it:
            if not control_var_correct and parsed.get('conditioning_visible'):
                score += 25  # Partial recovery
                feedback_parts.append("VLM confirmed partial correlation setup")
            
            # Basic visual confirmation points (10 pts)
            if parsed.get('analysis_visible') and parsed.get('scatter_plot_visible'):
                score += 10
                feedback_parts.append("Visual confirmation of analysis")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Cap score
    score = min(score, 100)
    
    # Pass logic: Must have file and correct control variable logic (either programmatic or visual)
    passed = (score >= 70) and (control_var_correct or ("VLM confirmed" in str(feedback_parts)))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }