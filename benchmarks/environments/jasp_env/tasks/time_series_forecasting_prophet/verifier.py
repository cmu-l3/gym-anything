#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_time_series_forecasting_prophet(traj, env_info, task_info):
    """
    Verifies the JASP Time Series Forecasting task.
    
    Criteria:
    1. Output file PassengerForecast.jasp exists and is a valid ZIP.
    2. File was created during the task (anti-gaming).
    3. JASP analysis contains evidence of Prophet module usage.
    4. Forecast horizon is set to 12.
    5. Variables 'Passengers' and 'Month' are used.
    """
    
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'PassengerForecast.jasp')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 2. Retrieve Task Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 3. Verify File Existence & Creation Time (Anti-Gaming)
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found. Did you save as 'PassengerForecast.jasp'?"}
    
    score += 10 # File exists
    
    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("Warning: Output file timestamp indicates it wasn't modified during this session.")
        # We penalize but don't fail immediately, in case of clock skew, but it's suspicious.
    else:
        score += 10 # File created during task
        
    # 4. Retrieve and Inspect the .jasp File
    # .jasp files are ZIP archives containing JSON analysis definitions and results
    local_jasp_path = os.path.join(tempfile.gettempdir(), expected_filename)
    try:
        copy_from_env(task_result['output_path'], local_jasp_path)
        
        if not zipfile.is_zipfile(local_jasp_path):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid JASP archive."}
        
        with zipfile.ZipFile(local_jasp_path, 'r') as z:
            file_list = z.namelist()
            
            # Search for analysis content
            # JASP structure usually has an 'index.html' or 'embedded/...' or JSONs defining the state
            # We look for specific keywords in the analysis specifications
            
            prophet_found = False
            horizon_found = False
            variables_found = False
            
            # Scan all text-based files in the archive for keywords
            # This is a robust heuristic method that works across JASP versions
            for fname in file_list:
                if fname.endswith('.json') or fname.endswith('.html') or fname.endswith('.qml'):
                    try:
                        with z.open(fname) as content_file:
                            content = content_file.read().decode('utf-8', errors='ignore')
                            
                            # Check for Module/Analysis Name
                            if "Prophet" in content or "prophet" in content.lower():
                                prophet_found = True
                                
                            # Check for Parameters (Horizon = 12)
                            # JASP saves options often like "periods": 12 or similar keys
                            if '"periods": 12' in content or '"periods":12' in content or "periods=12" in content or "12 months" in content:
                                horizon_found = True
                            
                            # Check for Variables
                            if "Passengers" in content and "Month" in content:
                                variables_found = True
                    except:
                        continue
            
            # Scoring based on content analysis
            if prophet_found:
                score += 30
                feedback_parts.append("Prophet module usage detected.")
            else:
                feedback_parts.append("Could not confirm Prophet module usage in file.")
                
            if variables_found:
                score += 25
                feedback_parts.append("Correct variables (Passengers, Month) detected.")
            else:
                feedback_parts.append("Could not confirm correct variables were used.")
                
            if horizon_found:
                score += 25
                feedback_parts.append("Forecast horizon of 12 detected.")
            else:
                feedback_parts.append("Could not confirm forecast horizon of 12.")

    except Exception as e:
        feedback_parts.append(f"Error inspecting JASP file: {str(e)}")
    finally:
        if os.path.exists(local_jasp_path):
            os.unlink(local_jasp_path)

    # 5. Finalize Score
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }