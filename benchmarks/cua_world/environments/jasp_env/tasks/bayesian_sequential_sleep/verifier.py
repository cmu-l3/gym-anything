#!/usr/bin/env python3
"""
Verifier for bayesian_sequential_sleep task.
Checks if the agent correctly configured a Bayesian T-Test in JASP with:
- Normal Prior (Mean=0, SD=1)
- Sequential Analysis Plot
- Descriptive Statistics
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_sequential_sleep(traj, env_info, task_info):
    """
    Verifies the JASP task by inspecting the saved .jasp file structure
    and performing visual verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (Anti-Gaming)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "JASP output file not found."}
    
    score += 10
    feedback_parts.append("File created")

    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp suggests it wasn't created during this session")
    else:
        score += 10
        feedback_parts.append("Timestamp valid")

    # 3. Analyze .jasp File Content
    # JASP files are ZIP archives containing JSON analysis specs
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    analysis_found = False
    prior_correct = False
    sequential_correct = False
    descriptives_correct = False
    vars_correct = False

    try:
        # Copy the .jasp file from container
        # Note: export_result.sh copies it to /tmp/submission.jasp
        copy_from_env("/tmp/submission.jasp", temp_jasp.name)
        
        with zipfile.ZipFile(temp_jasp.name, 'r') as z:
            # JASP structure varies, but usually contains JSON files defining the state.
            # We look for files that might contain the analysis definition.
            # Often located in 'embedded' folder or root as .json files.
            
            # Helper to recursively search JSON objects
            def find_analysis_spec(obj):
                nonlocal analysis_found, prior_correct, sequential_correct, descriptives_correct, vars_correct
                
                if isinstance(obj, dict):
                    # Check for Analysis Type
                    if "analysis" in obj and obj.get("analysis") == "TTestBayesianIndependentSamples":
                        analysis_found = True
                        
                    # Check settings if we are in the right analysis object or sub-object
                    # Note: JASP JSON structure is deeply nested options
                    
                    # Check Prior - look for specific keys JASP uses for Normal prior
                    # This is heuristic based on JASP's internal naming
                    if "priorFamily" in obj and obj["priorFamily"] == "Normal":
                        prior_correct = True
                    
                    # Check Sequential Analysis
                    if "sequentialAnalysis" in obj and obj["sequentialAnalysis"] is True:
                        sequential_correct = True
                        
                    # Check Descriptives
                    if "descriptives" in obj and obj["descriptives"] is True:
                        descriptives_correct = True
                        
                    # Check Variables (roughly)
                    if "variables" in obj or "dependent" in obj:
                        # Convert dict to string to lazy search for variable names
                        s_obj = json.dumps(obj)
                        if "extra" in s_obj and "group" in s_obj:
                            vars_correct = True

                    # Recursion
                    for k, v in obj.items():
                        find_analysis_spec(v)
                elif isinstance(obj, list):
                    for item in obj:
                        find_analysis_spec(item)

            # Iterate through all files in zip, try to parse JSONs
            for filename in z.namelist():
                if filename.endswith(".json"):
                    try:
                        with z.open(filename) as f:
                            content = json.load(f)
                            find_analysis_spec(content)
                    except:
                        pass
                # Sometimes analysis is embedded in HTML or other text formats in older versions,
                # but modern JASP uses JSON/R-state.
                # If JSON parsing misses it, we fallback to string search in the raw file content for robustness.
                if not prior_correct:
                    try:
                        with z.open(filename) as f:
                            raw = f.read().decode('utf-8', errors='ignore')
                            if "TTestBayesianIndependentSamples" in raw:
                                analysis_found = True
                            if '"priorFamily":"Normal"' in raw or '"priorFamily": "Normal"' in raw:
                                prior_correct = True
                            if '"sequentialAnalysis":true' in raw or '"sequentialAnalysis": true' in raw:
                                sequential_correct = True
                            if '"descriptives":true' in raw or '"descriptives": true' in raw:
                                descriptives_correct = True
                            if '"extra"' in raw and '"group"' in raw:
                                vars_correct = True
                    except:
                        pass

    except Exception as e:
        feedback_parts.append(f"Error parsing JASP file: {str(e)}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # Score Programmatic Checks
    if analysis_found:
        score += 10
        feedback_parts.append("Correct Analysis Type")
    else:
        feedback_parts.append("Wrong/Missing Analysis Type")

    if vars_correct:
        score += 10
        feedback_parts.append("Variables assigned")
    
    if prior_correct:
        score += 30
        feedback_parts.append("Prior set to Normal (Success)")
    else:
        feedback_parts.append("Prior NOT set to Normal (Check failed)")

    if sequential_correct:
        score += 15
        feedback_parts.append("Sequential Analysis enabled")
    else:
        feedback_parts.append("Sequential Analysis missing")

    if descriptives_correct:
        score += 5
        feedback_parts.append("Descriptives enabled")

    # 4. VLM Verification (Visual Confirmation)
    # We use VLM to check if the specific Sequential Analysis plot is visible
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = (
            "Analyze this JASP interface screenshot. "
            "1. Is a Bayesian Independent Samples T-Test visible? "
            "2. Is there a 'Sequential Analysis' plot visible (usually a line chart with red/white/green zones)? "
            "3. Is the Prior set to 'Normal' visible in the settings panel? "
            "Return JSON with keys: bayesian_test_visible (bool), sequential_plot_visible (bool), prior_normal_visible (bool)."
        )
        
        vlm_res = query_vlm(
            prompt=prompt,
            images=[final_screenshot]
        )
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('bayesian_test_visible'):
                # Reinforce analysis score if programmatic missed it
                if not analysis_found: score += 10 
            if parsed.get('sequential_plot_visible'):
                score += 10
                feedback_parts.append("VLM confirmed Sequential Plot")
            if parsed.get('prior_normal_visible'):
                # Visual confirmation of setting
                if not prior_correct: score += 10
                feedback_parts.append("VLM confirmed Normal Prior setting")
        else:
            feedback_parts.append("VLM verification failed")

    # Final logic
    passed = score >= 70 and prior_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }