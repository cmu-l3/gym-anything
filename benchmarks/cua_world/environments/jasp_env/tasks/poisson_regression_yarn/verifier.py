#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_poisson_regression_yarn(traj, env_info, task_info):
    """
    Verifies that the agent correctly performed a Poisson Regression in JASP.
    
    Checks:
    1. JASP file exists and was created during the task.
    2. JASP file is a valid ZIP archive.
    3. JSON content inside the JASP file contains a Generalized Linear Model.
    4. Model family is Poisson.
    5. Variables (Dependent: breaks, Factors: wool, tension) are correct.
    6. Estimated Marginal Means for 'tension' were requested.
    """
    
    # 1. Setup and Retrieve Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load the basic result info exported by shell script
    result_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    # 2. Check File Existence and Timestamps (Anti-Gaming)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'YarnBreaks_Poisson.jasp' not found."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task."}
        
    if result_data.get("file_size", 0) < 1000:
        return {"passed": False, "score": 0, "feedback": "Output file is too small to be a valid JASP project."}

    # 3. Retrieve and Inspect the JASP File
    jasp_file_path = tempfile.mktemp(suffix=".jasp")
    extract_dir = tempfile.mkdtemp()
    
    score = 20 # Points for creating the file
    feedback = ["File created successfully."]
    passed = False
    
    try:
        copy_from_env(result_data["output_path"], jasp_file_path)
        
        # JASP files are ZIP archives containing JSON definitions
        try:
            with zipfile.ZipFile(jasp_file_path, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "Output file is not a valid JASP/ZIP archive."}

        # 4. Find and Parse Analysis JSON
        # JASP structure varies, but usually contains JSON files defining analyses.
        # We look for any JSON that contains "GeneralizedLinearModel".
        analysis_found = False
        config_correct = False
        emmeans_found = False
        
        # Recursive search for JSON files
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                if file.endswith(".json"):
                    try:
                        with open(os.path.join(root, file), 'r') as f:
                            content = f.read()
                            
                        # Check for Analysis Type
                        if "GeneralizedLinearModel" in content or "generalizedLinearModel" in content:
                            analysis_found = True
                            data = json.loads(content)
                            
                            # Navigate JSON structure usually: "results" -> "0" -> "status" ... or "settings"
                            # We'll search generically in the dict for key settings
                            
                            # Helper to search deep dict
                            def find_key(obj, key):
                                if key in obj: return obj[key]
                                if isinstance(obj, dict):
                                    for k, v in obj.items():
                                        res = find_key(v, key)
                                        if res is not None: return res
                                if isinstance(obj, list):
                                    for v in obj:
                                        res = find_key(v, key)
                                        if res is not None: return res
                                return None

                            # Look for 'family' setting
                            # In JASP JSON, settings are often list of keys or dicts
                            # e.g. "family": "poisson", "link": "log"
                            
                            # Convert full json string to lower for easy substring search if structure is complex
                            content_lower = content.lower()
                            
                            # Verify Family
                            if '"family": "poisson"' in content_lower or '"family":"poisson"' in content_lower:
                                score += 20
                                feedback.append("Correct Family (Poisson) selected.")
                                
                                # Verify Variables
                                if '"breaks"' in content_lower and '"wool"' in content_lower and '"tension"' in content_lower:
                                    score += 20
                                    feedback.append("Correct variables assigned.")
                                    config_correct = True
                                else:
                                    feedback.append("Incorrect variable assignment.")
                            else:
                                feedback.append("Incorrect Family (Expected Poisson).")

                            # Verify Marginal Means
                            # Look for emmeans configuration or the variable 'tension' in an emmeans context
                            if "emmeans" in content_lower and '"tension"' in content_lower:
                                emmeans_found = True
                                score += 20
                                feedback.append("Estimated Marginal Means requested.")
                            
                            # If we found the specific analysis, we can stop looking
                            if config_correct:
                                break
                    except:
                        continue
            if config_correct: break

        if analysis_found:
            score += 20
            feedback.append("Generalized Linear Model analysis found.")
        else:
            feedback.append("No Generalized Linear Model analysis found in file.")

        if score >= 80:
            passed = True
            
    except Exception as e:
        feedback.append(f"Error inspecting JASP file: {str(e)}")
    finally:
        if os.path.exists(jasp_file_path):
            os.remove(jasp_file_path)
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }