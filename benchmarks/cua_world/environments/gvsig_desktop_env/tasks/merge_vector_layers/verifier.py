#!/usr/bin/env python3
"""
Verifier for merge_vector_layers task in gvSIG Desktop.

Verifies:
1. Output file exists and was created during task session.
2. Feature count matches sum of input files (approx 177).
3. Attributes are preserved and geometry is correct.
4. Data content spans multiple continents (prevents just copying one input).
5. VLM verification of UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_vector_layers(traj, env_info, task_info):
    """
    Verify the merge vector layers task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve programmatic result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Anti-Gaming (30 pts) ---
    output_exists = result.get("output_exists", False)
    created_during = result.get("created_during_task", False)
    output_size = result.get("output_size_bytes", 0)

    if output_exists and created_during and output_size > 1000:
        score += 30
        feedback.append("Output file created successfully.")
    elif output_exists:
        score += 10
        feedback.append("Output file exists but timestamp is invalid (pre-existing?).")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": "Fail: Output file not created."}

    # --- Criterion 2: Data Integrity (40 pts) ---
    feature_count = int(result.get("feature_count", 0))
    expected_count = int(result.get("expected_feature_count", 177))
    continents = int(result.get("distinct_continents", 0))
    
    # Allow small tolerance (+/- 5 features)
    diff = abs(feature_count - expected_count)
    
    if diff <= 5 and feature_count > 0:
        score += 25
        feedback.append(f"Feature count correct ({feature_count}).")
    elif feature_count > 0:
        score += 10
        feedback.append(f"Feature count mismatch: got {feature_count}, expected ~{expected_count}.")
    else:
        feedback.append("File contains no features.")

    if continents >= 5:
        score += 15
        feedback.append("Data covers all continents.")
    elif continents >= 2:
        score += 5
        feedback.append("Data covers some continents, but seemingly incomplete.")
    else:
        feedback.append("Data lacks continental diversity (likely only one input used).")

    # --- Criterion 3: Attribute & Geometry Check (10 pts) ---
    geom_type = result.get("geometry_type", "Unknown")
    attrs_ok = result.get("attributes_preserved", False)
    
    if "Polygon" in geom_type or "MultiPolygon" in geom_type:
        score += 5
    if attrs_ok:
        score += 5
        
    # --- Criterion 4: VLM Process Verification (20 pts) ---
    # Ensure they used the GUI, not just command line magic (though unlikely in this env)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Review these screenshots of a GIS workflow in gvSIG Desktop. "
            "The user should have: \n"
            "1. Opened a 'Geoprocess' or 'Geoprocessing' dialog (specifically Merge/Union).\n"
            "2. Selected input layers.\n"
            "3. Produced a map view showing the whole world.\n\n"
            "Do you see evidence of the Geoprocessing tool usage or the resulting world map? "
            "Reply 'YES' if the workflow looks correct, 'NO' otherwise."
        )
        
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if "YES" in vlm_response.upper():
            score += 20
            feedback.append("VLM verified geoprocessing workflow.")
        else:
            feedback.append("VLM could not clearly verify geoprocessing workflow.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: give partial credit if file is perfect
        if score >= 70:
            score += 10

    # Final Pass/Fail Logic
    passed = (score >= 70) and output_exists and (diff <= 5)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }