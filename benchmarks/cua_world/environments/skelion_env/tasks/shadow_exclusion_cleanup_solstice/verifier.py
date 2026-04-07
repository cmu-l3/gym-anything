#!/usr/bin/env python3
"""
Verifier for the Shadow Exclusion Cleanup task.
Combines exact geometric evaluation extracted via Ruby with VLM visual confirmation.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a user's progress in a SketchUp 3D modeling task.
Look at these screenshots showing the trajectory of their work.

1. Did the user open the "Shadows" tray/dialog at any point?
2. Are shadows visibly enabled and casting onto the roof/panels in the 3D view in at least one frame?

Return JSON exactly like this:
{
    "shadow_dialog_visible": true/false,
    "shadows_cast_in_scene": true/false
}
"""

def verify_shadow_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    expected_month = metadata.get('expected_month', 12)
    expected_day = metadata.get('expected_day', 21)
    expected_hour = metadata.get('expected_hour', 10)
    
    # Shadow zone is North-West of the chimney (which is at X=4.5-5.5, Y=3.0-4.0)
    # At Dec 21 10:00 AM in Boulder CO, shadow projects into X < 4.5 and Y > 4.5
    zone_max_x = metadata.get('shadow_zone_max_x', 4.5)
    zone_min_y = metadata.get('shadow_zone_min_y', 4.5)

    score = 0
    feedback_parts = []
    
    # 1. Fetch programmatic data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/workspace/final_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Base checks (File exists & Anti-gaming)
    file_exists = result.get('file_exists', False)
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Failure: shadow_cleanup_complete.skp was not saved."}
        
    if file_mtime > task_start:
        score += 10
        feedback_parts.append("✅ File saved during task.")
    else:
        feedback_parts.append("❌ File timestamp is invalid (gaming suspected).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Analyze Ruby Model State
    ruby_data = result.get('ruby_data', {})
    if 'error' in ruby_data:
        return {"passed": False, "score": score, "feedback": f"Ruby API error: {ruby_data['error']}"}

    # Evaluate Shadows State
    if ruby_data.get('shadows_on'):
        score += 10
        feedback_parts.append("✅ Shadows enabled in model.")
    else:
        feedback_parts.append("❌ Shadows were not left enabled.")

    # Evaluate Date and Time
    shadow_time_str = ruby_data.get('shadow_time_iso', '').replace('Z', '+00:00')
    try:
        dt = datetime.fromisoformat(shadow_time_str)
        
        if dt.month == expected_month and dt.day == expected_day:
            score += 15
            feedback_parts.append(f"✅ Date is correct ({dt.strftime('%b %d')}).")
        else:
            feedback_parts.append(f"❌ Incorrect Date (Expected Dec 21, found {dt.strftime('%b %d')}).")

        if dt.hour == expected_hour:
            score += 15
            feedback_parts.append(f"✅ Time is correct ({expected_hour}:00).")
        else:
            feedback_parts.append(f"❌ Incorrect Time (Expected {expected_hour}:00, found {dt.hour}:00).")
            
    except ValueError:
        feedback_parts.append("❌ Could not parse shadow time from model.")

    # Evaluate Panel Geometry Deletions
    panels = ruby_data.get('panels', [])
    panel_count = ruby_data.get('panel_count', 0)
    
    panels_in_shadow_zone = [p for p in panels if p['x'] < zone_max_x and p['y'] > zone_min_y]
    panels_outside_zone = [p for p in panels if not (p['x'] < zone_max_x and p['y'] > zone_min_y)]
    
    if len(panels_in_shadow_zone) == 0:
        score += 20
        feedback_parts.append("✅ All shaded panels were successfully pruned.")
    else:
        feedback_parts.append(f"❌ {len(panels_in_shadow_zone)} panels were left in the shadowed area.")

    # Prevent "delete everything" gaming strategy (15 unshaded panels should remain ideally)
    if len(panels_outside_zone) >= 12:
        score += 10
        feedback_parts.append("✅ Clean/unshaded panels were correctly preserved.")
    else:
        feedback_parts.append("❌ Too many clean panels were deleted.")

    # 4. VLM Trajectory Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
        if vlm_res and vlm_res.get('success'):
            vlm_parsed = vlm_res.get('parsed', {})
            if vlm_parsed.get('shadow_dialog_visible'):
                score += 10
                feedback_parts.append("✅ VLM confirmed shadows dialog was used.")
            if vlm_parsed.get('shadows_cast_in_scene'):
                score += 10
                feedback_parts.append("✅ VLM confirmed shadows were cast in the scene view.")

    # 5. Final Decision
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }