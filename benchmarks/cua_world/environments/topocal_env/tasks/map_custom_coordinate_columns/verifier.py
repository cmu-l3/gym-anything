#!/usr/bin/env python3
"""
Verifier for map_custom_coordinate_columns task.

Verification Strategy:
1. Validates output DXF file existence and timing (preventing pre-existing file hacks).
2. Parses DXF group codes (10 for X, 20 for Y) to programmatically ensure spatial orientation correctness.
3. Checks average coordinates against metadata boundaries to mathematically prove the agent properly mapped the schema in the UI before importing.
4. Uses VLM trajectory analysis to ensure the agent physically interacted with the UI import mapping schema.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_map_custom_coordinate_columns(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    correct_mapping = False

    # 1. Retrieve the exported JSON execution data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    
    result = {}
    dxf_exists = False
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        if result.get('output_exists'):
            copy_from_env("C:\\Users\\Docker\\Documents\\oriented_survey.dxf", temp_dxf.name)
            dxf_exists = True
    except Exception as e:
        logger.error(f"Failed to copy or read files from env: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Score file creation & size checks
    if dxf_exists:
        score += 10
        feedback_parts.append("DXF output file exists")
        
        if result.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("File created during active session")
        else:
            feedback_parts.append("WARNING: File timestamp precedes task start")
    else:
        feedback_parts.append("DXF output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Parse the DXF to analyze X and Y coordinates mapping
    x_coords = []
    y_coords = []
    
    try:
        with open(temp_dxf.name, 'r', encoding='utf-8', errors='ignore') as f:
            lines = [line.strip() for line in f.readlines()]
            
        in_entities = False
        for i in range(len(lines)):
            if lines[i] == 'ENTITIES':
                in_entities = True
            elif lines[i] == 'ENDSEC' and in_entities:
                in_entities = False
                
            if in_entities:
                if lines[i] == '10' and i + 1 < len(lines):
                    try:
                        val = float(lines[i+1])
                        # Filter to avoid picking up 0,0 origin lines or minor layer defaults
                        if 100000 < val < 5000000:
                            x_coords.append(val)
                    except ValueError:
                        pass
                elif lines[i] == '20' and i + 1 < len(lines):
                    try:
                        val = float(lines[i+1])
                        if 100000 < val < 5000000:
                            y_coords.append(val)
                    except ValueError:
                        pass
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # 4. Evaluate Spatial Alignment constraints
    if not x_coords or not y_coords:
        feedback_parts.append("DXF exists but contains no valid coordinate points")
    else:
        avg_x = sum(x_coords) / len(x_coords)
        avg_y = sum(y_coords) / len(y_coords)
        
        # Expected correct bounds (X: 493k, Y: 4.4M)
        if 400000 < avg_x < 600000 and 4000000 < avg_y < 5000000:
            score += 50
            correct_mapping = True
            feedback_parts.append(f"Correct schema mapping verified programmatically (Avg X: {avg_x:.0f}, Avg Y: {avg_y:.0f})")
        # Bounds of the typical error (swapped X and Y)
        elif 4000000 < avg_x < 5000000 and 400000 < avg_y < 600000:
            feedback_parts.append(f"FAILED: Coordinates swapped! Agent imported with default P X Y Z settings (Avg X: {avg_x:.0f}, Avg Y: {avg_y:.0f})")
        else:
            feedback_parts.append(f"Coordinates found but are wildly outside expected boundaries (Avg X: {avg_x:.0f}, Avg Y: {avg_y:.0f})")

    # 5. VLM Trajectory Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=6)
        
        if frames:
            prompt = """You are evaluating a trajectory of an AI agent using TopoCal.
The agent's task was to import a CSV point file and modify the default column mappings from 'P X Y Z' to 'P Y X Z' (mapping Northing to Y and Easting to X).
Review the screenshots carefully. Do you see the agent interacting with an import dialog ("Importar Puntos ASCII" or similar) and physically changing column mappings or selecting the correct radio button schema?

Respond in JSON:
{
    "import_dialog_visible": true/false,
    "mapping_modified": true/false,
    "reasoning": "brief explanation"
}"""
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("import_dialog_visible") and parsed.get("mapping_modified"):
                    score += 30
                    feedback_parts.append("VLM confirmed import dialog mapping modification")
                else:
                    feedback_parts.append("VLM did not observe mapping modification in dialog")
            else:
                feedback_parts.append(f"VLM query failed: {vlm_res.get('error')}")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification unavailable/failed")

    # Pass Criteria
    passed = score >= 70 and correct_mapping

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }