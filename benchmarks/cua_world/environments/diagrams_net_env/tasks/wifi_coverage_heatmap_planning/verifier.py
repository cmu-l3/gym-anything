#!/usr/bin/env python3
"""
Verifier for wifi_coverage_heatmap_planning task.

Verifies:
1. File Creation: .drawio and .png files exist.
2. Layer Structure: 3 distinct layers (Floor Plan, Hardware, Coverage).
3. Floor Plan: Layer is locked and contains an image.
4. Hardware: 3 AP icons present.
5. Coverage: Ellipses with transparency (opacity < 100).
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wifi_coverage_heatmap_planning(traj, env_info, task_info):
    """
    Verify the WiFi coverage task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Results
    score = 0
    feedback_parts = []
    
    analysis = result.get("analysis", {})
    
    # Criterion 1: Files Exist (20 pts)
    if result.get("drawio_file_exists"):
        score += 10
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file MISSING.")
        
    if result.get("export_file_exists") and result.get("export_file_size", 0) > 0:
        score += 10
        feedback_parts.append("Export PNG exists.")
    else:
        feedback_parts.append("Export PNG MISSING or empty.")

    # Criterion 2: Layer Management (30 pts)
    # Expecting at least 3 layers. Names should somewhat match instructions.
    layers = analysis.get("layers", [])
    layer_names = [l.get("name", "").lower() for l in layers]
    
    has_floor_layer = any("floor" in n for n in layer_names)
    has_hw_layer = any("hardware" in n for n in layer_names)
    has_cov_layer = any("coverage" in n for n in layer_names)
    
    if len(layers) >= 3:
        score += 10
        feedback_parts.append(f"Layer count OK ({len(layers)}).")
    else:
        feedback_parts.append(f"Insufficient layers ({len(layers)}/3).")

    if has_floor_layer and has_hw_layer and has_cov_layer:
        score += 20
        feedback_parts.append("Layer names correct.")
    elif has_floor_layer or has_hw_layer or has_cov_layer:
        score += 10
        feedback_parts.append("Some layer names correct.")

    # Criterion 3: Floor Plan Locking & Image (25 pts)
    if analysis.get("floor_plan_locked"):
        score += 15
        feedback_parts.append("Floor Plan layer is LOCKED.")
    else:
        feedback_parts.append("Floor Plan layer NOT locked.")
        
    if analysis.get("has_image"):
        score += 10
        feedback_parts.append("Image found on Floor Plan layer.")
    else:
        feedback_parts.append("No image found on correct layer.")

    # Criterion 4: Content (APs and Coverage) (25 pts)
    ap_count = analysis.get("ap_count", 0)
    if ap_count >= 3:
        score += 15
        feedback_parts.append(f"APs placed ({ap_count}/3).")
    elif ap_count > 0:
        score += 5
        feedback_parts.append(f"Partial APs ({ap_count}/3).")
        
    transparent_shapes = analysis.get("transparent_shapes", 0)
    if transparent_shapes >= 3:
        score += 10
        feedback_parts.append("Transparent coverage shapes found.")
    else:
        feedback_parts.append("Coverage shapes missing or not transparent.")

    # Final Pass Logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }