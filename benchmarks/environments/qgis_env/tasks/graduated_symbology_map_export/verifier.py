#!/usr/bin/env python3
"""
Verifier for graduated_symbology_map_export task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_graduated_symbology_map_export(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Saved a QGIS project file.
    2. Configured graduated symbology on the population field with >= 5 classes.
    3. Exported a non-trivial PNG map image.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    min_classes = metadata.get('min_classes', 5)
    target_field_fragment = "POP" # Matches POP_EST, POP_ESTIMATE, etc.

    # 2. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    logger.info(f"Verification Result Data: {result}")

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # --- Project File Checks (50 points) ---
    if result.get('project_found', False):
        score += 10
        feedback.append("Project file saved.")
        
        # Check Renderer
        renderer = result.get('renderer_type', '')
        if renderer == 'graduatedSymbol':
            score += 20
            feedback.append("Graduated symbology applied.")
        else:
            feedback.append(f"Incorrect symbology type: {renderer} (expected graduatedSymbol).")

        # Check Attribute Field
        attr = result.get('attribute_field', '')
        if target_field_fragment in attr.upper():
            score += 5
            feedback.append(f"Correct attribute field used: {attr}.")
        else:
            # Soft check - maybe they used a derived field, but give feedback
            feedback.append(f"Attribute field '{attr}' does not match expected population field.")

        # Check Class Count
        classes = result.get('class_count', 0)
        if classes >= min_classes:
            score += 15
            feedback.append(f"Sufficient classes created ({classes}).")
        elif classes > 0:
            score += 5
            feedback.append(f"Too few classes ({classes} < {min_classes}).")
        else:
            feedback.append("No classes defined in renderer.")
            
    else:
        feedback.append("Project file not found.")

    # --- Image Export Checks (50 points) ---
    if result.get('image_found', False):
        score += 10
        feedback.append("Map image exported.")
        
        # Dimensions
        w = result.get('image_width', 0)
        h = result.get('image_height', 0)
        if w >= 800 and h >= 600:
            score += 10
            feedback.append(f"Image dimensions valid ({w}x{h}).")
        else:
            score += 5
            feedback.append(f"Image too small ({w}x{h}).")
            
        # Content (Size and Color Variance)
        size_kb = result.get('image_size_kb', 0)
        colors = result.get('image_color_count', 0)
        
        # >50KB implies it's not just a tiny thumbnail or empty file
        if size_kb > 50:
            score += 15
            feedback.append("Image file size indicates content.")
        else:
            feedback.append(f"Image file suspiciously small ({size_kb} KB).")
            
        # >10 unique colors implies a map with symbology, not just a blank white/black canvas
        if colors > 10:
            score += 15
            feedback.append("Image contains visual data.")
        else:
            feedback.append("Image appears blank or monotone.")
            
    else:
        feedback.append("Exported image not found.")

    # 4. Final Verdict
    # Threshold: Must have project (10) + Graduated (20) + Image Exists (10) + Image Content (15) = 55 minimum
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }