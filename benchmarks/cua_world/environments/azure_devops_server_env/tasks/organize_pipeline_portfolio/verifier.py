#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_pipeline_portfolio(traj, env_info, task_info):
    """
    Verify that the 'Nightly Maintenance' pipeline was created, organized into the 
    'Operations' folder, and run successfully.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    # Note: Windows environment uses backslashes, but python string needs escaping or raw string
    remote_path = r"C:\Users\Docker\task_results\organize_pipeline_portfolio_result.json"
    
    # Create temp file to copy result to
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()

    try:
        copy_from_env(remote_path, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not retrieve task validation data. Did the export script run?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Criteria
    score = 0
    feedback = []

    # 1. Pipeline Exists (30 pts)
    if result.get('pipeline_found', False):
        score += 30
        feedback.append("Pipeline found.")
    else:
        feedback.append("Pipeline 'Nightly Maintenance' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Correct Path/Folder (30 pts)
    # API usually returns path with leading slash, e.g., "\Operations"
    path = result.get('pipeline_path', '')
    if '\\Operations' in path or '/Operations' in path:
        score += 30
        feedback.append("Pipeline is in the correct 'Operations' folder.")
    else:
        feedback.append(f"Pipeline is in wrong folder: '{path}' (Expected: 'Operations').")

    # 3. Correct YAML File (20 pts)
    yaml_file = result.get('yaml_filename', '')
    if 'maintenance-scripts.yml' in yaml_file:
        score += 20
        feedback.append("Pipeline correctly linked to 'maintenance-scripts.yml'.")
    else:
        feedback.append(f"Pipeline linked to wrong file: '{yaml_file}'.")

    # 4. Successful Run (20 pts)
    build_result = result.get('latest_build_result', '')
    if build_result == 'succeeded':
        score += 20
        feedback.append("Pipeline run verified successful.")
    elif build_result == 'failed':
        feedback.append("Pipeline ran but failed.")
    elif build_result == 'none':
        feedback.append("Pipeline has not been run.")
    else:
        feedback.append(f"Pipeline run status: {build_result}.")

    # Pass Threshold
    # Must have at least created it, put it in folder, and linked correct file (80 pts)
    # Running it is the last 20 pts
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }