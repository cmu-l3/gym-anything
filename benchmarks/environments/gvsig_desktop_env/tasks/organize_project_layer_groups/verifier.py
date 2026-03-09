#!/usr/bin/env python3
"""
Verifier for organize_project_layer_groups task.

Verification Strategy:
1. File Verification (30 pts):
   - Check if the .gvsproj file was created.
   - Check if it contains valid XML metadata.

2. Metadata Content Verification (30 pts):
   - Parse (or grep) the project XML for required strings:
     - "World Overview" (View Name)
     - "Physical Geography" (Group Name)
     - "Countries", "Rivers", "Cities" (Renamed Layers)

3. VLM Visual Verification (40 pts):
   - Inspect screenshot trajectory.
   - Confirm the visual hierarchy in the Table of Contents:
     - "Physical Geography" appears as a group/folder.
     - "Countries" and "Rivers" are indented/inside the group.
     - "Cities" is outside/above.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_project_layer_groups(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_view = metadata.get('required_view_name', "World Overview")
    required_group = metadata.get('required_group_name', "Physical Geography")
    required_layers = metadata.get('required_layer_names', ["Countries", "Rivers", "Cities"])

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Result Data
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    try:
        # Get JSON result
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Get extracted XML content if available
        xml_content = ""
        remote_xml_path = result.get("xml_extract_path")
        if remote_xml_path and result.get("project_exists"):
            try:
                copy_from_env(remote_xml_path, temp_xml.name)
                with open(temp_xml.name, 'r', encoding='utf-8', errors='ignore') as f:
                    xml_content = f.read()
            except Exception as e:
                logger.warning(f"Could not retrieve project XML: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # ------------------------------------------------------------------
    # 2. File Verification (30 Points)
    # ------------------------------------------------------------------
    if result.get("project_exists") and result.get("file_created_during_task"):
        score += 30
        feedback_parts.append("Project file created successfully.")
    elif result.get("project_exists"):
        score += 10
        feedback_parts.append("Project file exists but timestamp is old (reused?).")
    else:
        feedback_parts.append("Project file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ------------------------------------------------------------------
    # 3. XML Content Verification (30 Points)
    # ------------------------------------------------------------------
    # Since XML structure varies by version, we use robust substring matching
    xml_score = 0
    
    # Check View Name
    if required_view in xml_content:
        xml_score += 10
        feedback_parts.append(f"View renamed to '{required_view}'.")
    else:
        feedback_parts.append(f"View name '{required_view}' not found in project file.")

    # Check Group Name
    if required_group in xml_content:
        xml_score += 10
        feedback_parts.append(f"Group '{required_group}' found in metadata.")
    else:
        feedback_parts.append(f"Group '{required_group}' not found in metadata.")

    # Check Layer Names
    found_layers = [name for name in required_layers if name in xml_content]
    if len(found_layers) == len(required_layers):
        xml_score += 10
        feedback_parts.append("All layers renamed correctly in metadata.")
    else:
        # Partial credit
        xml_score += int(10 * len(found_layers) / len(required_layers))
        feedback_parts.append(f"Renamed {len(found_layers)}/{len(required_layers)} layers correctly.")

    score += xml_score

    # ------------------------------------------------------------------
    # 4. VLM Visual Verification (40 Points)
    # ------------------------------------------------------------------
    # We need to verify the *structure* (hierarchy), which flat text search can't confirm easily
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + [final_screen] if final_screen else frames

    prompt = f"""
    You are a GIS Project Auditor. Review these screenshots of gvSIG Desktop.
    
    The user was tasked with:
    1. Renaming layers to 'Countries', 'Rivers', 'Cities'.
    2. Creating a group named '{required_group}'.
    3. Putting 'Countries' and 'Rivers' INSIDE the group.
    4. Keeping 'Cities' OUTSIDE the group.
    5. Renaming the View to '{required_view}'.

    Please analyze the Table of Contents (TOC) panel (usually on the left):
    - Do you see the layer group '{required_group}'?
    - Are 'Countries' and 'Rivers' visually indented or nested under it?
    - Is 'Cities' separate from the group?
    - Is the window or view title '{required_view}'?
    
    Output JSON:
    {{
      "view_renamed": boolean,
      "group_created": boolean,
      "layers_renamed": boolean,
      "structure_correct": boolean,
      "explanation": "string"
    }}
    """
    
    try:
        vlm_resp = query_vlm(images, prompt)
        
        # Parse logic
        vlm_data = {}
        # Simple heuristic to handle potential markdown fencing in VLM response
        import re
        json_match = re.search(r'\{.*\}', vlm_resp, re.DOTALL)
        if json_match:
            vlm_data = json.loads(json_match.group(0))
        
        vlm_score = 0
        if vlm_data.get("group_created"): vlm_score += 10
        if vlm_data.get("layers_renamed"): vlm_score += 10
        if vlm_data.get("structure_correct"): vlm_score += 20
        
        score += vlm_score
        
        if vlm_data.get("structure_correct"):
            feedback_parts.append("Visual verification: Layer grouping structure is correct.")
        else:
            feedback_parts.append(f"Visual verification failed: {vlm_data.get('explanation', 'Structure incorrect')}")

    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if XML showed everything was perfect, give partial trust points
        if xml_score == 30:
            score += 20
            feedback_parts.append("VLM unavailable, trusting metadata for structure.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }