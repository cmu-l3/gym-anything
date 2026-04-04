#!/usr/bin/env python3
"""
Verifier for Paired Samples T-Test Task in JASP.
Verifies:
1. Output .jasp file exists and was created during task.
2. Content of .jasp file contains correct analysis (Paired T-Test).
3. Correct variables (Drug1, Drug2) were used.
4. Required options (Effect Size, Descriptives, Raincloud Plot) were enabled.
5. VLM verification of UI state.
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

def verify_paired_samples_ttest(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- 1. Load basic result metadata ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output .jasp file not found"}
    
    score += 10
    feedback_parts.append("File exists")

    if file_created:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp pre-dates task (anti-gaming fail)")

    if output_size < 1000:
        feedback_parts.append("File too small (<1KB)")
    else:
        score += 5

    # --- 2. Analyze .jasp file content ---
    # .jasp files are ZIP archives containing JSON definitions of analyses
    jasp_analysis_passed = False
    
    if output_exists and output_size > 1000:
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
        extract_dir = tempfile.mkdtemp()
        
        try:
            # Copy .jasp file from container
            copy_from_env(result['output_path'], temp_jasp.name)
            
            # Extract zip
            if zipfile.is_zipfile(temp_jasp.name):
                with zipfile.ZipFile(temp_jasp.name, 'r') as zip_ref:
                    zip_ref.extractall(extract_dir)
                
                # JASP structure usually has an 'analyses' folder or root JSONs
                # We search for any JSON containing analysis definitions
                analysis_found = False
                correct_vars = False
                opts_found = []
                
                # recursive search for json files
                for root, dirs, files in os.walk(extract_dir):
                    for file in files:
                        if file.endswith('.json'):
                            try:
                                with open(os.path.join(root, file), 'r') as f:
                                    content = f.read()
                                    
                                # Check for Paired T-Test
                                if 'ttestpairedsamples' in content.lower() or 'paired samples t-test' in content.lower():
                                    analysis_found = True
                                    
                                    # Check variables
                                    if 'drug1' in content.lower() and 'drug2' in content.lower():
                                        correct_vars = True
                                    
                                    # Check options
                                    if 'effectsize' in content.lower() or 'cohen' in content.lower():
                                        opts_found.append("Effect Size")
                                    if 'descriptives' in content.lower():
                                        opts_found.append("Descriptives")
                                    if 'raincloud' in content.lower():
                                        opts_found.append("Raincloud Plot")
                            except:
                                continue

                if analysis_found:
                    score += 20
                    feedback_parts.append("Paired T-Test analysis found")
                    jasp_analysis_passed = True
                else:
                    feedback_parts.append("Paired T-Test analysis NOT found in file")

                if correct_vars:
                    score += 10
                    feedback_parts.append("Correct variables used")
                
                # Score options (5 pts each, max 15)
                for opt in opts_found:
                    score += 5
                if opts_found:
                    feedback_parts.append(f"Options enabled: {', '.join(opts_found)}")

            else:
                feedback_parts.append("Invalid .jasp file format (not a zip)")

        except Exception as e:
            feedback_parts.append(f"Error analyzing .jasp file: {str(e)}")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)
            shutil.rmtree(extract_dir, ignore_errors=True)

    # --- 3. VLM Verification ---
    # Use trajectory frames to confirm UI interaction and final state
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        images = frames + [final_screen]
        prompt = """
        Review this sequence of screenshots from JASP statistical software.
        1. Did the user load a dataset with columns 'Drug1' and 'Drug2'?
        2. Is the 'Paired Samples T-Test' analysis visible?
        3. Are the results (tables/plots) visible in the right-hand panel?
        4. specifically, is there a 'Raincloud plot' (dots + distribution shapes) visible?
        
        Respond in JSON:
        {
            "dataset_loaded": true/false,
            "paired_ttest_visible": true/false,
            "results_panel_visible": true/false,
            "raincloud_plot_visible": true/false
        }
        """
        
        vlm_res = query_vlm(images=images, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('dataset_loaded'): score += 5
            if parsed.get('paired_ttest_visible'): score += 10
            if parsed.get('results_panel_visible'): score += 10
            if parsed.get('raincloud_plot_visible'): score += 5
            
            feedback_parts.append(f"VLM analysis: {json.dumps(parsed)}")
        else:
            feedback_parts.append("VLM analysis failed")

    # --- Final Scoring ---
    # Pass if file analysis passed AND significant score
    passed = jasp_analysis_passed and score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }