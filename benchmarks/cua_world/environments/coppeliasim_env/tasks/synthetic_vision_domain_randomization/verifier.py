#!/usr/bin/env python3
"""
Verifier for synthetic_vision_domain_randomization task.

Scoring System (100 points total):
- 20 points: CSV & JSON structural validity
- 20 points: Dataset Size (>= 20 images and rows)
- 25 points: Parameter Randomization (variance > 0 for color, rot, light)
- 20 points: Image Uniqueness (anti-gaming against copy-pasting images)
- 15 points: Image Validity (pixels contain meaningful content)

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_synthetic_vision(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env("/tmp/synthetic_vision_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read dataset result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # Criterion 1: CSV & JSON Structure (20 pts)
    struct_score = 0
    if result.get("csv_exists") and result.get("csv_is_new") and result.get("csv_has_headers"):
        struct_score += 10
        feedback.append("CSV structure valid (+10)")
    elif result.get("csv_exists"):
        struct_score += 5
        feedback.append("CSV exists but structure/headers incomplete (partial: 5/10)")
    else:
        feedback.append("metadata.csv not found")

    if result.get("json_exists") and result.get("json_is_new") and result.get("json_has_fields"):
        struct_score += 10
        feedback.append("JSON structure valid (+10)")
    elif result.get("json_exists"):
        struct_score += 5
        feedback.append("JSON exists but fields incomplete (partial: 5/10)")
    else:
        feedback.append("generation_report.json not found")
        
    score += struct_score

    # Criterion 2: Dataset Size (20 pts)
    csv_rows = int(result.get("csv_rows", 0))
    new_images = int(result.get("new_images", 0))
    
    if csv_rows >= 20 and new_images >= 20:
        score += 20
        feedback.append(f"Dataset size valid: {new_images} images, {csv_rows} CSV rows (+20)")
    elif csv_rows >= 5 or new_images >= 5:
        score += 10
        feedback.append(f"Dataset size partial: {new_images} images, {csv_rows} CSV rows (partial: 10/20)")
    else:
        feedback.append(f"Dataset too small: {new_images} images, {csv_rows} rows")

    # Criterion 3: Parameter Randomization (25 pts)
    csv_vars = result.get("csv_vars", {})
    var_color = float(csv_vars.get("color", 0.0))
    var_rot = float(csv_vars.get("rot", 0.0))
    var_light = float(csv_vars.get("light", 0.0))
    
    # Needs variance > threshold to prove it was truly randomized
    randomized_count = sum(1 for v in [var_color, var_rot, var_light] if v > 0.001)
    
    if randomized_count >= 2:
        score += 25
        feedback.append(f"Good domain randomization detected (color_var={var_color:.3f}, rot_var={var_rot:.3f}, light_var={var_light:.3f}) (+25)")
    elif randomized_count == 1:
        score += 10
        feedback.append("Partial domain randomization (partial: 10/25)")
    else:
        feedback.append("Parameters were static or barely randomized")

    # Criterion 4: Image Uniqueness (20 pts) - Anti-Gaming
    unique_hashes = int(result.get("unique_hashes", 0))
    image_count = int(result.get("image_count", 0))
    
    if image_count >= 20 and unique_hashes == image_count:
        score += 20
        feedback.append(f"All {image_count} images are unique (+20)")
    elif unique_hashes > 1 and unique_hashes >= image_count * 0.5:
        score += 10
        feedback.append(f"{unique_hashes}/{image_count} images are unique (partial: 10/20)")
    else:
        feedback.append(f"Images are mostly duplicates: {unique_hashes} unique out of {image_count}")

    # Criterion 5: Image Validity (15 pts) - Not just empty shapes/colors
    valid_images = int(result.get("valid_images", 0))
    mean_var = float(result.get("mean_pixel_var", 0.0))
    
    if valid_images >= 20 and mean_var > 5.0:
        score += 15
        feedback.append(f"Images are valid with rendering content (mean variance: {mean_var:.1f}) (+15)")
    elif valid_images >= 5 and mean_var > 0.0:
        score += 5
        feedback.append("Images are valid but have low variance or low count (partial: 5/15)")
    else:
        feedback.append("Images appear to be invalid or blank renders")

    # Final pass conditions:
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }