#!/usr/bin/env python3
"""
Verifier for generate_coordinate_grid task in TopoCal.

Verification Strategy (Multi-Signal):
1. FILE SYSTEM: Checks if DXF and TOP files were created/modified during the task timeframe.
2. FILE CONTENT: Sanity checks the exported DXF content for valid CAD structures.
3. VISUAL/TRAJECTORY: Uses VLM across the task trajectory to ensure the UI dialogs for 
   Grid (Cuadrícula) were actually used and configured to the required 50m intervals.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance in TopoCal topographic CAD.
The agent was tasked with creating a 50m x 50m cartographic coordinate grid (cuadrícula).

Examine these trajectory frames and the final screenshot:
1. Did the agent navigate to and open the Grid/Cuadrícula dialog (usually under Dibujo/Topografía)?
2. In the configuration dialog, were the X and Y intervals (Incrementos) set to 50?
3. In the final view, is a geometric grid (crosses or lines with text labels) visible overlaying the topographic points?

Respond in pure JSON format:
{
    "dialog_opened": true/false,
    "interval_configured": true/false,
    "grid_visible": true/false,
    "reasoning": "Brief explanation of what you observed"
}
"""

def verify_coordinate_grid(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    expected_interval = metadata.get('grid_interval', 50)
    
    score = 0
    feedback_parts = []
    
    # 1. RETRIEVE EXECUTION METADATA
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\workspace\\data\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    dxf_data = result_data.get('dxf', {})
    top_data = result_data.get('top', {})
    
    # 2. FILE EXISTENCE AND ANTI-GAMING TIMESTAMPS (40 points)
    dxf_valid = False
    if dxf_data.get('exists') and dxf_data.get('created_during_task'):
        if dxf_data.get('size_bytes', 0) > metadata.get('min_dxf_size_bytes', 1024):
            score += 25
            dxf_valid = True
            feedback_parts.append("DXF file successfully exported during task")
        else:
            feedback_parts.append("DXF file created but unusually small")
    else:
        feedback_parts.append("DXF file missing or pre-dates task execution")

    if top_data.get('exists') and top_data.get('created_during_task'):
        score += 15
        feedback_parts.append("Project TOP file successfully saved")
    else:
        feedback_parts.append("Project TOP file not saved during task")

    # 3. DXF FILE CONTENT SANITY CHECK (20 points)
    if dxf_valid:
        temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
        try:
            copy_from_env("C:\\workspace\\data\\foothills_grid_export.dxf", temp_dxf.name)
            with open(temp_dxf.name, 'r', encoding='utf-8', errors='ignore') as f:
                dxf_content = f.read()
                # Basic check for DXF standard sections to ensure it's not a dummy file
                if "SECTION" in dxf_content and "ENTITIES" in dxf_content:
                    score += 20
                    feedback_parts.append("DXF structural validation passed")
                else:
                    feedback_parts.append("DXF file exported but lacks standard ENTITIES section")
        except Exception as e:
            feedback_parts.append(f"Could not parse DXF file: {e}")
        finally:
            if os.path.exists(temp_dxf.name):
                os.unlink(temp_dxf.name)

    # 4. VLM TRAJECTORY VERIFICATION (40 points)
    # Using trajectory frames, not just the final screenshot to prevent spoofing
    vlm_passed = False
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if final_img:
            vlm_images = frames + [final_img]
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=vlm_images)
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("dialog_opened"):
                    score += 10
                    feedback_parts.append("VLM: Grid dialog usage confirmed")
                if parsed.get("interval_configured"):
                    score += 15
                    feedback_parts.append(f"VLM: Grid interval {expected_interval}m confirmed")
                if parsed.get("grid_visible"):
                    score += 15
                    vlm_passed = True
                    feedback_parts.append("VLM: Coordinate grid visible in viewport")
                
                logger.info(f"VLM Reasoning: {parsed.get('reasoning', 'None')}")
            else:
                feedback_parts.append("VLM evaluation failed to process")
        else:
            feedback_parts.append("No screenshots available for VLM verification")
    else:
        feedback_parts.append("VLM querying unavailable in this environment")

    # Define success criteria
    # Must have created the DXF file AND either passed the structural check or VLM visual check
    key_criteria_met = dxf_valid and (score >= 70)
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }