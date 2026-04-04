#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_macro_recording(traj, env_info, task_info):
    """
    Verifies that the agent recorded a Fiji macro with specific processing steps.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. Contains Background Subtraction with radius 50.
    3. Contains Median Filter with radius 2.
    4. Contains Otsu Thresholding.
    5. Contains command to convert to mask (Apply).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Results
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    content = result.get("macro_content", "")
    
    score = 0
    feedback = []

    # Criterion 1: File existence and freshness (20 pts)
    if file_exists and created_during:
        score += 20
        feedback.append("Macro file saved successfully.")
    elif file_exists:
        # Penalize if file is old (anti-gaming)
        score += 5
        feedback.append("Macro file found, but timestamp is old (reused?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Macro file 'clean_and_segment.ijm' not found."}

    # Normalize content for checking
    content_lower = content.lower()

    # Criterion 2: Background Subtraction (20 pts)
    # Expected: run("Subtract Background...", "rolling=50");
    if "subtract background" in content_lower and "50" in content_lower:
        score += 20
        feedback.append("Background subtraction recorded correctly (Radius 50).")
    elif "subtract background" in content_lower:
        score += 10
        feedback.append("Background subtraction found, but parameter 50 missing.")
    else:
        feedback.append("Missing 'Subtract Background' command.")

    # Criterion 3: Median Filter (20 pts)
    # Expected: run("Median...", "radius=2");
    if "median" in content_lower and "2" in content_lower:
        score += 20
        feedback.append("Median filter recorded correctly (Radius 2).")
    elif "median" in content_lower:
        score += 10
        feedback.append("Median filter found, but parameter 2 missing.")
    else:
        feedback.append("Missing 'Median' filter command.")

    # Criterion 4: Otsu Thresholding (20 pts)
    # Expected: setAutoThreshold("Otsu");
    if "autothreshold" in content_lower and "otsu" in content_lower:
        score += 20
        feedback.append("Otsu thresholding recorded correctly.")
    elif "otsu" in content_lower:
        score += 10
        feedback.append("Otsu method found, but command structure unclear.")
    else:
        feedback.append("Missing 'Otsu' threshold command.")

    # Criterion 5: Apply Threshold / Convert to Mask (20 pts)
    # Expected: run("Convert to Mask"); OR setOption("BlackBackground", ...); run("Convert to Mask");
    if "convert to mask" in content_lower or "apply" in content_lower:
        score += 20
        feedback.append("Threshold application (Convert to Mask) recorded.")
    else:
        feedback.append("Missing command to apply threshold (Convert to Mask).")

    # Final decision
    # Pass threshold: 80 points (must get almost everything right)
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }