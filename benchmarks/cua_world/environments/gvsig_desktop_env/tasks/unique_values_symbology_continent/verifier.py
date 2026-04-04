#!/usr/bin/env python3
"""
Verifier for unique_values_symbology_continent task.

Criteria:
1. Project file exists and contains 'Unique Values' configuration for 'CONTINENT'.
2. Exported map image exists.
3. VLM verification confirms the map shows distinct colors for continents.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_unique_values_symbology(traj, env_info, task_info):
    """
    Verifies that the agent applied unique values symbology and exported the map.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)."}

    metadata = task_info.get('metadata', {})
    project_path = metadata.get('project_path', '/home/ga/gvsig_data/projects/continent_categories.gvsproj')
    field_name = metadata.get('field_name', 'CONTINENT')

    # Load result JSON from container
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            task_result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Project File
    project_exists = task_result.get('project_exists', False)
    project_valid_time = task_result.get('project_created_during_task', False)
    
    project_content = ""
    if project_exists and project_valid_time:
        score += 20
        feedback_parts.append("Project file saved.")
        
        # Analyze project content
        with tempfile.NamedTemporaryFile(suffix=".gvsproj") as pf:
            try:
                copy_from_env(project_path, pf.name)
                with open(pf.name, 'r', encoding='utf-8', errors='ignore') as f:
                    project_content = f.read()
            except Exception as e:
                feedback_parts.append(f"Could not read project file: {e}")

        # Basic text-based XML check (gvSIG XML is verbose)
        # Look for the field name associated with classification
        if field_name in project_content:
            score += 15
            feedback_parts.append(f"Field '{field_name}' found in project configuration.")
        else:
            feedback_parts.append(f"Field '{field_name}' NOT found in project.")

        # Look for Symbology hints
        # "VectorialUniqueValueLegend" is the class name often used in gvSIG projects for categories
        if "UniqueValueLegend" in project_content or "VectorialUniqueValueLegend" in project_content:
            score += 15
            feedback_parts.append("Unique Values symbology detected in project.")
        else:
            feedback_parts.append("Unique Values symbology NOT detected in project XML.")
            
    elif project_exists:
        feedback_parts.append("Project file exists but has old timestamp (not saved during task?).")
    else:
        feedback_parts.append("Project file not saved.")

    # 2. Check Exported Image
    export_exists = task_result.get('export_exists', False)
    export_valid_time = task_result.get('export_created_during_task', False)
    export_size = task_result.get('export_size', 0)

    export_image_local = None

    if export_exists and export_valid_time and export_size > 10240: # >10KB
        score += 20
        feedback_parts.append("Map image exported successfully.")
        
        # Download image for VLM
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".png") as img_tmp:
                copy_from_env(metadata.get('export_path'), img_tmp.name)
                export_image_local = img_tmp.name
        except Exception:
            pass
    else:
        feedback_parts.append("Map image not exported or too small.")

    # 3. VLM Verification
    # We use the exported image if available, otherwise the final screenshot
    images_to_check = []
    
    # Add trajectory frames to context
    frames = sample_trajectory_frames(traj, n=3)
    images_to_check.extend(frames)
    
    # Add exported image if available (highest fidelity)
    if export_image_local:
        images_to_check.append(export_image_local)
    
    # Add final screenshot as fallback/context
    final_screen = get_final_screenshot(traj)
    if final_screen:
        images_to_check.append(final_screen)

    vlm_prompt = (
        "You are evaluating a GIS task. The user was supposed to apply a 'Unique Values' symbology "
        "to a world map based on Continents. \n"
        "Look at the images, especially the final map or exported image.\n"
        "1. Do you see a map of the world?\n"
        "2. Are the continents colored with DIFFERENT colors (e.g. Africa is one color, South America another)?\n"
        "3. Is there a legend visible showing categories?\n"
        "If the map is all one color, the task is failed.\n"
        "Answer 'YES' if the map is clearly categorized by color, 'NO' otherwise."
    )
    
    vlm_result = query_vlm(images_to_check, vlm_prompt)
    
    if "YES" in vlm_result.upper():
        score += 30
        feedback_parts.append("VLM confirms map is colored by category.")
    else:
        feedback_parts.append("VLM could not confirm distinct continent colors.")

    # Cleanup
    if export_image_local and os.path.exists(export_image_local):
        os.unlink(export_image_local)

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }