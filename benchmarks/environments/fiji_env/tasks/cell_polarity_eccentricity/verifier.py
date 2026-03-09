#!/usr/bin/env python3
import json
import os
import math

def verify_cell_polarity_eccentricity(traj, env_info, task_info):
    """
    Verify the Cell Polarity & Eccentricity task.
    
    Scoring Breakdown (100 pts):
    1. CSV file exists and has data (10 pts)
    2. Annotated Image exists (10 pts)
    3. Image is RGB Composite (Green/Red) (10 pts)
    4. Image contains annotations (white arrows/lines) (15 pts)
    5. Measurement Accuracy vs Ground Truth (40 pts)
    6. CSV format correctness (columns) (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load results
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Output Files Existence (20 pts total)
    if result.get("csv_exists"):
        score += 10
        feedback.append("CSV file found.")
    else:
        feedback.append("CSV file missing.")
        
    if result.get("image_exists"):
        score += 10
        feedback.append("Image file found.")
    else:
        feedback.append("Image file missing.")

    # 2. Image Checks (25 pts total)
    agent_img = result.get("agent_image", {})
    if agent_img.get("is_rgb"):
        score += 10
        feedback.append("Image is valid RGB composite.")
    else:
        feedback.append("Image is not RGB/Composite.")
        
    if agent_img.get("has_annotation"):
        score += 15
        feedback.append("Annotation detected in image.")
    else:
        feedback.append("No visible white annotation detected.")

    # 3. Measurement Accuracy (40 pts)
    gt = result.get("ground_truth", {})
    agent_csv = result.get("agent_csv", {})
    
    if gt.get("ground_truth_calculated") and agent_csv.get("valid"):
        gt_dist = gt.get("gt_displacement_um", 0)
        agent_dist = agent_csv.get("displacement", 0)
        
        # Tolerance: 15% (thresholding differences)
        error = abs(gt_dist - agent_dist)
        percent_error = (error / gt_dist) * 100 if gt_dist > 0 else 0
        
        if percent_error <= 15:
            score += 40
            feedback.append(f"Measurement accurate: {agent_dist:.2f}um vs GT {gt_dist:.2f}um.")
        elif percent_error <= 30:
            score += 20
            feedback.append(f"Measurement slightly off: {agent_dist:.2f}um vs GT {gt_dist:.2f}um.")
        else:
            feedback.append(f"Measurement inaccurate: {agent_dist:.2f}um vs GT {gt_dist:.2f}um.")
            
        # Optional: Check if coordinates roughly match (implies correct image used)
        # Not strictly scored to avoid double penalizing, but good for debug
    else:
        feedback.append("Cannot verify accuracy (GT or Agent data invalid).")

    # 4. CSV Formatting (15 pts)
    # We implicitly checked 'valid' earlier which checks for displacement column
    if agent_csv.get("valid"):
        # Check if coordinates were also extracted
        if "cell_x" in agent_csv and agent_csv["cell_x"] > 0:
            score += 15
            feedback.append("CSV contains required coordinate columns.")
        else:
            score += 5
            feedback.append("CSV missing coordinate columns, but has displacement.")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }