#!/usr/bin/env python3
"""
Verifier for build_multi_layer_map task in gvSIG Desktop.

Checks:
1. Project file exists and was created during the task.
2. Project file contains references to all 3 required shapefiles.
3. VLM verifies the visual result (map composition and layer ordering).
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_multi_layer_map(traj, env_info, task_info):
    """
    Verify that the user created a multi-layer map with correct data and ordering.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_layers = metadata.get('required_layers', [])
    min_size = metadata.get('min_file_size_bytes', 1024)

    score = 0
    feedback_parts = []
    
    # 1. Fetch result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (Anti-gaming)
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Project file not found at expected path."}

    if not created_during_task:
        feedback_parts.append("Warning: Project file timestamp is older than task start.")
        # We penalize heavily but continue checking content in case of clock skew, 
        # though strictly this should fail 0.
        score += 0 
    else:
        score += 10
        feedback_parts.append("Project file created during task.")

    if file_size < min_size:
        feedback_parts.append(f"Project file is too small ({file_size} bytes).")
    else:
        score += 5
        feedback_parts.append("Project file size is reasonable.")

    # 3. Analyze Project Content (gvSIG project is a ZIP)
    # We need to fetch the .gvsproj file
    project_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.gvsproj')
    project_valid = False
    layers_found = 0
    
    try:
        copy_from_env("/tmp/submitted_project.gvsproj", project_temp.name)
        
        if zipfile.is_zipfile(project_temp.name):
            with zipfile.ZipFile(project_temp.name, 'r') as z:
                # Concatenate all XML content to search for layer references
                # gvSIG usually stores metadata in files ending with .xml
                xml_content = ""
                for filename in z.namelist():
                    if filename.endswith('.xml') or filename.endswith('.gvp'):
                        try:
                            with z.open(filename) as f:
                                xml_content += f.read().decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for each required layer
                found_names = []
                for layer_req in required_layers:
                    layer_keywords = layer_req.get('keywords', [])
                    # Check if any keyword matches
                    match = any(kw.lower() in xml_content.lower() for kw in layer_keywords)
                    if match:
                        layers_found += 1
                        found_names.append(layer_req['name'])
                
                if layers_found == 3:
                    score += 45
                    feedback_parts.append(f"All 3 required layers found in project ({', '.join(found_names)}).")
                elif layers_found > 0:
                    score += (layers_found * 15)
                    feedback_parts.append(f"Found {layers_found}/3 layers ({', '.join(found_names)}).")
                else:
                    feedback_parts.append("No required layers found in project file metadata.")
                
                project_valid = True
        else:
            feedback_parts.append("Project file is not a valid ZIP archive.")
            
    except Exception as e:
        feedback_parts.append(f"Error analyzing project file: {str(e)}")
    finally:
        if os.path.exists(project_temp.name):
            os.unlink(project_temp.name)

    # 4. VLM Verification (Visual Check)
    # We use trajectory frames to ensure the work was done and final state is correct
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if not frames:
        feedback_parts.append("No screenshots available for visual verification.")
    else:
        # Construct VLM prompt
        prompt = (
            "You are verifying a GIS task in gvSIG Desktop. "
            "The user was asked to create a map with 3 layers in this specific order (bottom to top):\n"
            "1. Countries (Polygons/Fill)\n"
            "2. Rivers (Lines)\n"
            "3. Cities (Points)\n\n"
            "Look at the screenshots. Can you confirm:\n"
            "A) The map shows land polygons, river lines, and city points?\n"
            "B) The layers are visible and correctly ordered (Points on top of Lines on top of Polygons)?\n"
            "C) The Table of Contents (left panel) lists these layers?\n\n"
            "Answer yes/no and explain."
        )
        
        try:
            vlm_result = query_vlm(images=frames, prompt=prompt)
            feedback_parts.append(f"VLM Analysis: {vlm_result}")
            
            # Simple keyword scoring based on VLM response
            vlm_lower = vlm_result.lower()
            if "yes" in vlm_lower and ("confirm" in vlm_lower or "correct" in vlm_lower):
                score += 40
            elif "partially" in vlm_lower:
                score += 20
            else:
                # If programmatically correct but VLM unsure, give benefit of doubt if layers found
                if layers_found == 3:
                    score += 20
        except Exception as e:
            logger.error(f"VLM query failed: {e}")
            # Fallback points if programmatic check passed heavily
            if layers_found == 3:
                score += 20

    # Final Pass/Fail Determination
    # Must have created file + found at least 2 layers + reasonable score
    passed = (created_during_task and layers_found >= 2 and score >= 60)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }