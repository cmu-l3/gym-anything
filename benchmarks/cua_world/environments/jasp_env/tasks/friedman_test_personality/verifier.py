#!/usr/bin/env python3
"""
Verifier for Friedman Test task in JASP.
Parses the saved .jasp file (ZIP archive) to verify analysis settings.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_jasp_analysis(jasp_file_path):
    """
    Extracts the 'analysis' configuration from a .jasp file.
    JASP files are ZIPs containing JSON configs.
    We look for the JSON describing the specific analysis.
    """
    if not os.path.exists(jasp_file_path):
        return None

    try:
        with zipfile.ZipFile(jasp_file_path, 'r') as z:
            # JASP structure varies, but usually contains an 'embedded' folder or root JSONs
            # We look for a file containing the analysis definition
            # Often named '1-analysis-name.json' or found in 'analyses' list in index/metadata
            
            # Strategy: List all JSON files and search for "friedman"
            json_files = [f for f in z.namelist() if f.endswith('.json')]
            
            for json_file in json_files:
                try:
                    with z.open(json_file) as f:
                        data = json.load(f)
                        # Check if this JSON describes our Repeated Measures analysis
                        # JASP JSONs are often nested. We look for specific keys.
                        
                        # Convert to string for broad search first to save time
                        str_dump = json.dumps(data)
                        if "friedman" in str_dump:
                            return data
                except:
                    continue
    except Exception as e:
        logger.error(f"Error unzipping JASP file: {e}")
        return None
        
    return None

def find_key_value_recursive(obj, target_key):
    """Recursively search for a key in a nested dict/list and return its value."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == target_key:
                return v
            res = find_key_value_recursive(v, target_key)
            if res is not None:
                return res
    elif isinstance(obj, list):
        for item in obj:
            res = find_key_value_recursive(item, target_key)
            if res is not None:
                return res
    return None

def verify_friedman_test(traj, env_info, task_info):
    """
    Verifies the Friedman test task.
    1. Checks JASP file existence and creation time.
    2. Parses JASP file to verify Friedman test and Kendall's W were enabled.
    3. Verifies correct variables were used.
    4. Uses VLM as backup/supplement.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        # Check basic file existence
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "JASP output file not found."}
            
        if not result_data.get('file_created_during_task', False):
            return {"passed": False, "score": 0, "feedback": "JASP file was not created during the task (stale file)."}

        # Copy the actual JASP file for inspection
        if result_data.get('output_exists'):
            copy_from_env("/tmp/Friedman_Analysis.jasp", temp_jasp.name)

        # 2. Parse JASP file content
        score = 0
        feedback = []
        
        analysis_data = extract_jasp_analysis(temp_jasp.name)
        
        has_friedman = False
        has_kendall = False
        correct_vars = False
        
        if analysis_data:
            # Check for Friedman option
            # In JASP JSON, options are usually keys like "friedman" set to true
            # or in a settings object
            
            # Robust check: look for "friedman" set to True/true
            # Note: JASP JSONs might use boolean true or string "true"
            friedman_val = find_key_value_recursive(analysis_data, "friedman")
            if friedman_val is True or friedman_val == "true":
                has_friedman = True
                score += 30
                feedback.append("Friedman test enabled.")
            else:
                feedback.append("Friedman test NOT enabled.")

            # Check for Kendall's W
            kendall_val = find_key_value_recursive(analysis_data, "kendallsW")
            if kendall_val is True or kendall_val == "true":
                has_kendall = True
                score += 20
                feedback.append("Kendall's W enabled.")
            else:
                feedback.append("Kendall's W NOT enabled.")
                
            # Check variables
            # We look for the variable names in the configuration
            str_dump = json.dumps(analysis_data)
            required = metadata.get("required_variables", [])
            forbidden = metadata.get("forbidden_variables", [])
            
            vars_present = [v for v in required if v in str_dump]
            vars_forbidden_present = [v for v in forbidden if v in str_dump]
            
            if len(vars_present) == len(required) and len(vars_forbidden_present) == 0:
                correct_vars = True
                score += 20
                feedback.append("Correct variables selected.")
            else:
                feedback.append(f"Variable selection issue. Found {len(vars_present)}/{len(required)} required.")
                if vars_forbidden_present:
                    feedback.append(f"Included forbidden variables: {vars_forbidden_present}")

            # Base score for valid file
            score += 10
            
        else:
            feedback.append("Could not parse JASP file content (invalid format or empty).")

        # 3. VLM Verification (Trajectory)
        # Use VLM to confirm the UI interaction if file parsing is ambiguous or to boost confidence
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Review these screenshots of a user using JASP statistical software. "
            "Did the user perform the following steps?\n"
            "1. Navigate to ANOVA > Repeated Measures ANOVA.\n"
            "2. Select the variables Neuroticism, Extraversion, and Openness.\n"
            "3. Check the 'Friedman' test option under Nonparametrics.\n"
            "4. Check 'Kendall's W'.\n"
            "Answer with JSON: {'steps_observed': [], 'confidence': 'low/high'}"
        )
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_score = 0
        if vlm_result and isinstance(vlm_result, dict):
            # Simple heuristic for VLM score
            content = str(vlm_result)
            if "Friedman" in content or "friedman" in content:
                vlm_score += 10
            if "Repeated Measures" in content:
                vlm_score += 10
        
        # Add VLM score component (max 20 pts)
        score += vlm_score
        feedback.append(f"VLM verification added {vlm_score} points.")

        # Final score calculation
        passed = score >= 80 and has_friedman
        
        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)