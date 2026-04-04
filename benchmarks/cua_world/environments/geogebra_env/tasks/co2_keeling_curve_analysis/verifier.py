#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_co2_analysis(traj, env_info, task_info):
    """
    Verify the Keeling Curve CO2 Analysis task.
    
    Criteria:
    1. File creation (10 pts)
    2. Data Import (> 100 points) (20 pts)
    3. Trend Model (FitPoly/FitExp) (20 pts)
    4. Cycle Model (FitSin/Sin) (20 pts)
    5. Combined Model/Prediction Accuracy (30 pts)
       - Prediction for May 2030 should be roughly 438-455 ppm
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_min_ppm = metadata.get('prediction_min_ppm', 438.0)
    expected_max_ppm = metadata.get('prediction_max_ppm', 455.0)

    # 2. Retrieve Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Grading
    score = 0
    feedback = []
    
    # A. File Existence (10)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully.")
    elif result.get("file_found"):
        score += 5
        feedback.append("File found but not created during this session.")
    else:
        feedback.append("File 'co2_analysis.ggb' not found.")
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # B. Data Import (20)
    # Real dataset has ~600+ points. We expect at least 100.
    pt_count = result.get("data_points_count", 0)
    if pt_count > 100:
        score += 20
        feedback.append(f"Data import successful ({pt_count} points).")
    elif pt_count > 10:
        score += 10
        feedback.append(f"Partial data import ({pt_count} points).")
    else:
        feedback.append("Insufficient data points found.")

    # C. Trend Model (20)
    if result.get("has_trend_model"):
        score += 20
        feedback.append("Trend model detected.")
    else:
        feedback.append("Trend model (FitPoly/FitExp) not detected.")

    # D. Cycle Model (20)
    if result.get("has_cycle_model"):
        score += 20
        feedback.append("Seasonal cycle model detected.")
    else:
        feedback.append("Cycle model (Sine wave) not detected.")

    # E. Prediction Accuracy (30)
    has_pred = result.get("has_prediction")
    pred = result.get("prediction_coords", {"x": 0, "y": 0})
    px, py = pred.get("x", 0), pred.get("y", 0)
    
    if has_pred:
        # Check Date: May 2030 is ~2030.375. Allow wide range for year.
        if 2029.5 <= px <= 2031.5:
            # Check Value
            if expected_min_ppm <= py <= expected_max_ppm:
                score += 30
                feedback.append(f"Prediction accurate: {py:.2f} ppm at {px:.2f}.")
            else:
                score += 10
                feedback.append(f"Prediction found but value suspect ({py:.2f} ppm). Expected {expected_min_ppm}-{expected_max_ppm}.")
        else:
            score += 5
            feedback.append(f"Prediction point found but wrong year ({px:.2f}).")
    else:
        feedback.append("Prediction point not found.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }