#!/usr/bin/env python3
import os
import re
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_query_elevations(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent correctly interpolated elevations from the TopoCal TIN.
    Includes VLM trajectory checks to ensure the tool was genuinely used.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}
        
    metadata = task_info.get('metadata', {})
    expected_points = metadata.get('query_points', {})
    tol_xy = metadata.get('tolerance_xy', 1.5)
    tol_z = metadata.get('tolerance_z', 2.5)
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    # ==========================================
    # 1. READ EXPORTED RESULTS
    # ==========================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use Windows absolute path for the container file
        copy_from_env("C:/temp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # ==========================================
    # 2. FILE EXISTENCE & TIMESTAMPS
    # ==========================================
    if not result.get('output_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file building_pad_elevations.txt was not created.",
            "details": result
        }
        
    score += 10
    feedback_parts.append("File exists (+10)")
    
    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during session (+10)")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start (Possible gaming)")

    # ==========================================
    # 3. CONTENT PARSING & GEOMETRY CHECK
    # ==========================================
    content = result.get('file_content', '')
    lines = [line.strip() for line in content.split('\n') if line.strip()]
    
    if len(lines) >= 4:
        score += 10
        feedback_parts.append("File contains expected line count (+10)")
    else:
        feedback_parts.append(f"File only contains {len(lines)} lines")

    # Helper to parse [X, Y, Z] from a string line safely
    def parse_xyz(line_str):
        numbers = re.findall(r'-?\d+(?:\.\d+)?', line_str)
        if len(numbers) >= 3:
            return float(numbers[-3]), float(numbers[-2]), float(numbers[-1])
        return None

    # Track matches
    matched_xy = 0
    matched_z = 0
    
    for corner, exp in expected_points.items():
        found = False
        for line in lines:
            parsed = parse_xyz(line)
            if not parsed:
                continue
            x, y, z = parsed
            
            # Check if this line corresponds to the expected coordinate pair
            if abs(x - exp['x']) <= tol_xy and abs(y - exp['y']) <= tol_xy:
                matched_xy += 1
                found = True
                
                # Check if the Z elevation matches the expected interpolation
                if abs(z - exp['z']) <= tol_z:
                    matched_z += 1
                break
                
        if not found:
            logger.info(f"Did not find matching X/Y coordinates for {corner} ({exp['x']}, {exp['y']})")

    xy_score = matched_xy * 5
    z_score = matched_z * 5
    score += xy_score
    score += z_score
    
    feedback_parts.append(f"Matched XY coordinates: {matched_xy}/4 (+{xy_score})")
    feedback_parts.append(f"Accurate Z interpolations: {matched_z}/4 (+{z_score})")
    
    # ==========================================
    # 4. VLM TRAJECTORY VERIFICATION (Anti-Gaming)
    # ==========================================
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # We need to verify the TIN was built and the app interacted with
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_prompt = """
        Review these screenshots from a CAD task in TopoCal.
        Answer the following in JSON format:
        {
            "tin_mesh_visible": true/false,
            "evidence_of_query_tool_used": true/false
        }
        "tin_mesh_visible" should be true if a triangulated terrain mesh (lines connecting points to form triangles) is visible on the drawing area.
        "evidence_of_query_tool_used" should be true if you see dialogue boxes, crosshairs, coordinate readouts, or text editors logging coordinates.
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('tin_mesh_visible'):
                score += 15
                feedback_parts.append("VLM confirmed TIN mesh creation (+15)")
            else:
                feedback_parts.append("VLM did not detect a TIN mesh.")
                
            if parsed.get('evidence_of_query_tool_used'):
                score += 15
                feedback_parts.append("VLM confirmed interaction with query/coordinate tools (+15)")
        else:
            feedback_parts.append("VLM query failed, lost 30 process verification points.")

    # ==========================================
    # FINAL SCORING
    # ==========================================
    # Requirement: Must have created the file, found at least 2 correct Zs, and passed passing threshold.
    is_valid_attempt = result.get('file_created_during_task', False) and (matched_z >= 2)
    passed = (score >= 60) and is_valid_attempt
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_content": content,
            "matched_xy": matched_xy,
            "matched_z": matched_z
        }
    }