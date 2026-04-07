#!/usr/bin/env python3
"""
Verifier for the Gambrel Roof Solar Installation Task.

VERIFICATION METRICS:
1. File Modified: Verifies the agent saved the file back to the specified path.
2. Location Configuration: Ensures latitude was properly set via Skelion / Model Info.
3. Selective Surface Placement (Upper Faces): Checks that panels exist on the ~25° faces.
4. Selective Surface Restriction (Lower Faces): Crucial check ensuring NO panels exist on >45° faces.
5. VLM Verification: Combines programmatic state with visual workflow checks to prevent false positives.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are evaluating an agent interacting with SketchUp and the Skelion plugin.
The agent was asked to design a solar layout on a gambrel roof building.

Look at the provided trajectory frames and the final screenshot. Determine:
1. Did the agent open the Skelion plugin dialog at some point?
2. In the final screenshot, are there solar panels visually present on the building's roof?
3. Specifically, are the panels ONLY placed on the upper (shallow-sloped) portions of the roof?
4. Are the lower (steep) sides of the roof completely EMPTY of solar panels?

Reply in JSON format:
{
    "skelion_used": true/false,
    "panels_visible_on_roof": true/false,
    "panels_only_on_upper_roof": true/false,
    "steep_sides_empty": true/false
}
"""

def verify_gambrel_solar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_lat', 40.04)
    upper_min = metadata.get('upper_slope_min', 15)
    upper_max = metadata.get('upper_slope_max', 40)
    lower_min = metadata.get('lower_slope_min', 45)

    score = 0
    feedback_parts = []
    
    # 1. Fetch the exported JSON state
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Evaluation
    file_modified = result.get('file_modified', False)
    panels = result.get('panels', [])
    latitude = result.get('latitude', 0.0)

    upper_panels = 0
    lower_panels = 0

    for panel in panels:
        slope = panel.get('slope', 0)
        if upper_min <= slope <= upper_max:
            upper_panels += 1
        elif slope >= lower_min:
            lower_panels += 1

    # Criterion A: File was saved (10 pts)
    if file_modified:
        score += 10
        feedback_parts.append("✅ File was saved")
    else:
        feedback_parts.append("❌ File was not modified (agent didn't save)")

    # Criterion B: Location configuration (10 pts)
    # Check if latitude is around 40.04 (+/- 1 degree)
    if abs(latitude - target_lat) < 1.0:
        score += 10
        feedback_parts.append("✅ Geographic location correctly set to PA")
    else:
        feedback_parts.append(f"❌ Location incorrect (Lat: {latitude:.2f})")

    # Criterion C: Panel creation on upper roof (30 pts)
    if upper_panels >= 4:
        score += 30
        feedback_parts.append(f"✅ Found {upper_panels} panels correctly on the upper roof faces")
    elif upper_panels > 0:
        score += 15
        feedback_parts.append(f"⚠️ Only {upper_panels} panels on upper roof (expected more)")
    else:
        feedback_parts.append("❌ No panels found on the upper roof faces")

    # Criterion D: Strict negative constraint - No panels on lower steep faces (25 pts)
    # Only award if panels exist overall, otherwise "do nothing" earns points
    if lower_panels == 0 and len(panels) > 0:
        score += 25
        feedback_parts.append("✅ Steep lower roof faces successfully left empty")
    elif lower_panels > 0:
        feedback_parts.append(f"❌ FAILED CONSTRAINT: {lower_panels} panels incorrectly placed on steep lower roof")
    else:
        feedback_parts.append("❌ No panels were created overall")

    # 3. VLM Visual Workflow & State Verification (25 pts)
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if final_img:
            vlm_response = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=frames + [final_img]
            )
            
            if vlm_response.get('success'):
                vlm_parsed = vlm_response.get('parsed', {})
                skelion_used = vlm_parsed.get('skelion_used', False)
                upper_only = vlm_parsed.get('panels_only_on_upper_roof', False)
                sides_empty = vlm_parsed.get('steep_sides_empty', False)
                
                if skelion_used:
                    score += 10
                    feedback_parts.append("✅ VLM: Skelion plugin usage detected")
                
                if upper_only and sides_empty:
                    score += 15
                    vlm_passed = True
                    feedback_parts.append("✅ VLM: Visually confirms correct layout on gambrel geometry")
                else:
                    feedback_parts.append("❌ VLM: Layout visually incorrect or steep sides contain panels")

    # Determine final passage
    key_criteria_met = (
        file_modified and 
        upper_panels >= 4 and 
        lower_panels == 0
    )
    
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "total_panels": len(panels),
            "upper_panels": upper_panels,
            "lower_panels": lower_panels,
            "latitude": latitude
        }
    }