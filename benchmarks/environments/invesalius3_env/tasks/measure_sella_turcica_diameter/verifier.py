#!/usr/bin/env python3
"""
Verifier for measure_sella_turcica_diameter task.

Goal: Verify the agent located the Sella Turcica (pituitary fossa) and measured its diameter.
Context: Sella Turcica AP diameter is typically 10-16 mm.

Scoring Criteria:
1. File Creation (20 pts): Project file exists and was created during task.
2. Valid Format (20 pts): File is a valid InVesalius project.
3. Measurement Recorded (20 pts): At least one measurement exists.
4. Accuracy (40 pts): At least one measurement is within 5-25 mm range.
   - This range excludes whole-skull measurements (>100mm)
   - Excludes single-pixel clicks (<2mm)
   - Broad enough to account for placement variability but specific to small structures.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measure_sella_turcica_diameter(traj, env_info, task_info):
    """
    Verify the sella turcica measurement task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Retrieve result JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/sella_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Freshness (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Project saved successfully")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("Project exists but timestamp check failed")
    else:
        feedback_parts.append("Project file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid Format (20 pts)
    if result.get("valid_inv3"):
        score += 20
        feedback_parts.append("Valid project format")
    else:
        feedback_parts.append("Invalid or corrupted project file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Measurement Recorded (20 pts)
    count = result.get("measurement_count", 0)
    all_vals = result.get("all_measurements", [])
    
    if count > 0:
        score += 20
        feedback_parts.append(f"Recorded {count} measurement(s)")
    else:
        feedback_parts.append("No measurements found in project")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 4: Accuracy / Anatomical Target (40 pts)
    # The Sella Turcica is small. Whole skull measurements are large.
    valid_vals = result.get("valid_measurements", [])
    
    if len(valid_vals) > 0:
        score += 40
        feedback_parts.append(f"Measurement within valid anatomical range ({valid_vals[0]:.1f} mm)")
    else:
        # Provide helpful feedback on what was measured
        if all_vals:
            avg_val = sum(all_vals) / len(all_vals)
            if avg_val > 100:
                feedback_parts.append(f"Measurement too large ({avg_val:.1f} mm) - likely measured whole skull instead of Sella Turcica")
            else:
                feedback_parts.append(f"Measurement value ({avg_val:.1f} mm) outside expected range (5-25 mm)")
        else:
            feedback_parts.append("No valid measurements found")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "measurements": all_vals,
            "valid_measurements": valid_vals
        }
    }