#!/usr/bin/env python3
"""
Verifier for create_facility_map task.

Verifies:
1. Layout "Warehouse Map" exists.
2. Background image is set to "warehouse_plan.png".
3. "Entrance Camera" is positioned in the bottom half.
4. "Server Room Camera" is positioned in the top-right quadrant.
5. VLM verification of the visual map.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_facility_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. API Verification
    layout_found = result.get('layout_found', False)
    layout_data = result.get('layout_data', {})
    device_map = result.get('device_map', {}) # id -> name
    
    # ID reverse lookup
    name_to_id = {v: k for k, v in device_map.items()}
    entrance_id = name_to_id.get("Entrance Camera")
    server_id = name_to_id.get("Server Room Camera")

    if layout_found:
        score += 20
        feedback_parts.append("Layout 'Warehouse Map' created")
        
        # Check Background
        bg_file = layout_data.get('backgroundImageFilename', '')
        if 'warehouse_plan.png' in bg_file:
            score += 30
            feedback_parts.append("Background image correct")
        else:
            feedback_parts.append(f"Background incorrect/missing (found: {bg_file})")
            
        # Check Items
        items = layout_data.get('items', [])
        
        entrance_item = next((i for i in items if i.get('resourceId') == entrance_id), None)
        server_item = next((i for i in items if i.get('resourceId') == server_id), None)
        
        # Check Entrance Camera Position (Bottom Center)
        # Coordinate system in Nx API:
        # usually relative (0-1) or grid. 
        # 'top', 'left', 'width', 'height'
        # Larger 'top' value = lower on screen.
        if entrance_item:
            # Assuming relative coords 0.0 to 1.0 (typical for API v1 layouts)
            # OR grid coordinates. 
            # Heuristic: If we have multiple items, Entrance should be lower (higher Y/top) than Server.
            
            top = float(entrance_item.get('top', 0))
            left = float(entrance_item.get('left', 0))
            
            # Simple check: Is it in the bottom half? (top > 0.5 if normalized, or just relative to server)
            # We'll use relative check if server exists, otherwise absolute check assuming normalized
            
            pos_ok = False
            if server_item:
                server_top = float(server_item.get('top', 0))
                if top > server_top:
                    pos_ok = True
            
            if pos_ok:
                score += 20
                feedback_parts.append("Entrance Camera positioned below Server Camera")
            else:
                feedback_parts.append("Entrance Camera positioning issue")
        else:
            feedback_parts.append("Entrance Camera NOT found on layout")
            
        # Check Server Room Camera Position (Top Right)
        if server_item:
            left = float(server_item.get('left', 0))
            
            # Check if it's on the right (left > 0.5 or right of entrance)
            pos_ok = False
            if entrance_item:
                entrance_left = float(entrance_item.get('left', 0))
                if left > entrance_left or left > 0.5:
                    pos_ok = True
            elif left > 0.5:
                pos_ok = True
                
            if pos_ok:
                score += 20
                feedback_parts.append("Server Camera positioned correctly (Top/Right)")
            else:
                feedback_parts.append("Server Camera positioning issue")
        else:
            feedback_parts.append("Server Room Camera NOT found on layout")
            
    else:
        feedback_parts.append("Layout 'Warehouse Map' NOT found")

    # 2. VLM Verification (Visual Check)
    # The API check for coordinates can be flaky if units are grid-based. 
    # VLM is the ultimate truth for "Does this look like a map?"
    
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        vlm_prompt = """
        You are verifying a task in Nx Witness VMS.
        The user was asked to create a layout with a specific floor plan background.
        
        Look at the screenshot.
        1. Do you see a white map/floor plan background with labels like "MAIN ENTRANCE" or "SERVER ROOM"?
        2. Are there camera feeds (video tiles) placed ON this map?
        3. Is there a camera near the "MAIN ENTRANCE" label (bottom)?
        4. Is there a camera near the "SERVER ROOM" label (top right)?
        
        Respond JSON: {"map_visible": bool, "cameras_on_map": bool, "positioning_correct": bool}
        """
        
        try:
            vlm_res = query_vlm(
                images=frames + [final_img],
                prompt=vlm_prompt
            )
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('map_visible'):
                score += 5
                # If API failed background check (maybe file path issue), VLM can save points
                if "Background incorrect" in str(feedback_parts):
                    score += 10 
                    feedback_parts.append("(VLM confirmed map is visible despite API mismatch)")
            
            if parsed.get('positioning_correct'):
                score += 5
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Pass logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }