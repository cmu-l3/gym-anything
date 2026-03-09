#!/usr/bin/env python3
"""
Verifier for scene_collection_organization task.
Verifies that objects are sorted into correct collections and visibility is set.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scene_organization(traj, env_info, task_info):
    """
    Verify the Blender scene organization.
    
    Criteria:
    1. File saved & modified (15 pts)
    2. 'Geometry' collection contains all 7 meshes (20 pts)
    3. 'Lighting' collection contains all 3 lights (20 pts)
    4. 'Cameras' collection contains all 2 cameras (15 pts)
    5. 'Helpers' collection contains all 2 empties (15 pts)
    6. 'Helpers' collection is hidden in viewport (10 pts)
    7. Default collection is empty/clean (5 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback_parts = []
    passed = False

    # 1. File checks (15 pts)
    if result.get("file_exists") and result.get("file_valid") and result.get("file_modified_during_task"):
        score += 15
        feedback_parts.append("File saved successfully")
    else:
        feedback_parts.append("File missing or not saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Analysis data
    scene = result.get("scene_analysis", {})
    collections = scene.get("collections", {})
    
    # 2. Geometry Collection (20 pts)
    # Expect 7 MESH objects
    geo_col = collections.get("Geometry", {})
    geo_objs = geo_col.get("objects", [])
    mesh_count = sum(1 for o in geo_objs if o["type"] == "MESH")
    
    if mesh_count == 7:
        score += 20
        feedback_parts.append("Geometry collection correct")
    elif mesh_count > 0:
        # Partial credit
        partial = int(20 * (mesh_count / 7))
        score += partial
        feedback_parts.append(f"Geometry partial ({mesh_count}/7)")
    else:
        feedback_parts.append("Geometry collection missing/empty")

    # 3. Lighting Collection (20 pts)
    # Expect 3 LIGHT objects
    light_col = collections.get("Lighting", {})
    light_objs = light_col.get("objects", [])
    light_count = sum(1 for o in light_objs if o["type"] == "LIGHT")
    
    if light_count == 3:
        score += 20
        feedback_parts.append("Lighting collection correct")
    elif light_count > 0:
        partial = int(20 * (light_count / 3))
        score += partial
        feedback_parts.append(f"Lighting partial ({light_count}/3)")
    else:
        feedback_parts.append("Lighting collection missing/empty")

    # 4. Cameras Collection (15 pts)
    # Expect 2 CAMERA objects
    cam_col = collections.get("Cameras", {})
    cam_objs = cam_col.get("objects", [])
    cam_count = sum(1 for o in cam_objs if o["type"] == "CAMERA")
    
    if cam_count == 2:
        score += 15
        feedback_parts.append("Cameras collection correct")
    elif cam_count > 0:
        partial = int(15 * (cam_count / 2))
        score += partial
        feedback_parts.append(f"Cameras partial ({cam_count}/2)")
    else:
        feedback_parts.append("Cameras collection missing/empty")

    # 5. Helpers Collection (15 pts)
    # Expect 2 EMPTY objects
    help_col = collections.get("Helpers", {})
    help_objs = help_col.get("objects", [])
    empty_count = sum(1 for o in help_objs if o["type"] == "EMPTY")
    
    if empty_count == 2:
        score += 15
        feedback_parts.append("Helpers collection correct")
    elif empty_count > 0:
        partial = int(15 * (empty_count / 2))
        score += partial
        feedback_parts.append(f"Helpers partial ({empty_count}/2)")
    else:
        feedback_parts.append("Helpers collection missing/empty")

    # 6. Helpers Visibility (10 pts)
    if "Helpers" in collections:
        if collections["Helpers"].get("hide_viewport") is True:
            score += 10
            feedback_parts.append("Helpers hidden")
        else:
            feedback_parts.append("Helpers visible (should be hidden)")

    # 7. Orphans (5 pts)
    # Check if default "Collection" is empty or missing
    orphans = scene.get("orphans_in_default", [])
    if len(orphans) == 0:
        score += 5
        feedback_parts.append("Clean hierarchy")
    else:
        feedback_parts.append(f"{len(orphans)} objects left in default collection")

    # Check for object deletion (Anti-gaming)
    total_objects = scene.get("total_objects", 0)
    if total_objects < 14:
        score = max(0, score - 20) # Penalty for deleting objects
        feedback_parts.append(f"PENALTY: Objects deleted ({total_objects}/14)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }