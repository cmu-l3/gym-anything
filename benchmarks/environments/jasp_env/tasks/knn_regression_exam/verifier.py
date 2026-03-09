#!/usr/bin/env python3
"""
Verifier for JASP KNN Regression task.
Verifies the .jasp output file structure and settings.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_knn_regression_exam(traj, env_info, task_info):
    """
    Verify the agent correctly configured and saved the KNN regression analysis.
    
    Criteria:
    1. Output .jasp file exists and was created during task.
    2. JASP file is a valid zip archive containing analyses.json.
    3. Analysis type is KNN Regression.
    4. Target variable is 'Exam'.
    5. Feature variables include 'Anxiety' and 'Revise'.
    6. K (neighbors) is set to 5.
    7. Seed is set to 42.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/JASP/knn_exam_results.jasp')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)
            
    # Check basic file existence and timing
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .jasp file not found."}
        
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp is too old (not created during task)."}
    
    score += 20
    feedback_parts.append("JASP file created.")

    # 2. Retrieve and Inspect JASP file content
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env(expected_output, temp_jasp.name)
        
        # JASP files are ZIP archives
        if not zipfile.is_zipfile(temp_jasp.name):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid JASP archive."}
            
        with zipfile.ZipFile(temp_jasp.name, 'r') as z:
            z.extractall(extract_dir)
            
        # Check for analyses.json
        analysis_path = os.path.join(extract_dir, "analyses.json")
        if not os.path.exists(analysis_path):
            return {"passed": False, "score": score, "feedback": "Invalid JASP file: analyses.json missing."}
            
        score += 10 # Valid JASP structure
        
        with open(analysis_path, 'r') as f:
            analyses = json.load(f)
            
        # Find KNN Regression analysis
        # Name might vary slightly by version, checking "title" or "name"
        knn_analysis = None
        for analysis in analyses:
            title = analysis.get("title", "").lower()
            name = analysis.get("name", "").lower()
            if "knn" in title or "nearest neighbor" in title or "knn" in name:
                knn_analysis = analysis
                break
        
        if not knn_analysis:
            return {"passed": False, "score": score, "feedback": "No KNN Regression analysis found in file."}
            
        score += 15
        feedback_parts.append("KNN Regression analysis found.")
        
        options = knn_analysis.get("options", {})
        
        # 3. Verify Target (Dependent Variable)
        # Key is usually "target" or "dependent"
        target = options.get("target") or options.get("dependent")
        if target == "Exam":
            score += 15
            feedback_parts.append("Target variable correct.")
        else:
            feedback_parts.append(f"Incorrect target variable: {target}")

        # 4. Verify Features (Predictors)
        # Key is usually "predictors" or "features"
        predictors = options.get("predictors") or options.get("features") or []
        # Allow for list or single string
        if isinstance(predictors, str):
            predictors = [predictors]
            
        required_features = ["Anxiety", "Revise"]
        features_correct = all(feat in predictors for feat in required_features)
        
        if features_correct:
            score += 15
            feedback_parts.append("Feature variables correct.")
        else:
            feedback_parts.append(f"Incorrect features. Found: {predictors}")

        # 5. Verify K (Neighbors)
        # Key: "noOfNearestNeighbours"
        k_val = options.get("noOfNearestNeighbours")
        if k_val == 5:
            score += 10
            feedback_parts.append("Neighbors (K=5) correct.")
        else:
            feedback_parts.append(f"Incorrect K value: {k_val}")

        # 6. Verify Seed
        # Keys: "seed" and "setSeed"
        seed_val = options.get("seed")
        set_seed = options.get("setSeed", False)
        
        if int(seed_val) == 42 and set_seed:
            score += 10
            feedback_parts.append("Seed (42) correct.")
        else:
            feedback_parts.append(f"Incorrect seed settings (Val: {seed_val}, Set: {set_seed})")

        # 7. Verify Plot (Predicted vs Observed)
        # Key: "plotPredictedVsObserved"
        if options.get("plotPredictedVsObserved", False):
            score += 5
            feedback_parts.append("Predicted vs Observed plot enabled.")
        else:
            feedback_parts.append("Plot not enabled.")

    except Exception as e:
        logger.error(f"Error validating JASP content: {e}")
        return {"passed": False, "score": score, "feedback": f"Error validating JASP file: {e}"}
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }