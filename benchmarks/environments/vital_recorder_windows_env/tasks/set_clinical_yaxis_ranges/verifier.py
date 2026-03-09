#!/usr/bin/env python3
"""
Verifier for set_clinical_yaxis_ranges task.

Criteria:
1. Agent saved a screenshot (20 pts)
   - Must be created during task
   - Must be > 10KB
2. VLM Analysis of Final State (80 pts)
   - HR track Y-axis range [40-160]
   - SpO2 track Y-axis range [85-100]
   - ART track Y-axis range [30-200]
   - Interactions visible in trajectory
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_yaxis_ranges(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 1. Parse JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows style but copy_from_env handles the mapping
        # In the container, we wrote to C:\temp\set_clinical_yaxis_ranges\task_result.json
        # Docker path might be /c/temp/... or just C:\... depending on driver. 
        # Usually standard linux paths work for mapped drives, but for Windows containers we use the path inside.
        # Assuming the tool handles the path string correctly.
        copy_from_env("C:\\temp\\set_clinical_yaxis_ranges\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 2. Check File Existence (20 pts)
    output_exists = result_data.get('output_exists', False)
    created_fresh = result_data.get('file_created_during_task', False)
    size = result_data.get('output_size_bytes', 0)

    if output_exists and created_fresh and size > 10000:
        score += 20
        feedback_parts.append("✅ Screenshot saved successfully")
    elif output_exists:
        score += 10
        feedback_parts.append("⚠️ Screenshot exists but timestamp/size verification failed")
    else:
        feedback_parts.append("❌ No screenshot saved")

    # 3. VLM Verification (80 pts)
    # We analyze the FINAL state from the trajectory or the system screenshot
    # We use trajectory frames to ensure they actually used the menu
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
         return {"passed": False, "score": score, "feedback": "No video feed available for verification"}

    # PROMPT CONSTRUCTION
    prompt = """
    You are verifying a clinical software task. The user was asked to set specific Y-axis ranges for vital signs tracks.
    
    Look at the Final Screenshot and check the Y-axis labels on the left side of the tracks.
    
    Target Settings:
    1. HR (Heart Rate, usually top/green): Range should be 40 to 160.
    2. SpO2 (Oxygen, usually blue): Range should be 85 to 100.
    3. ART (Arterial BP, usually red): Range should be 30 to 200.
    
    Also look at the trajectory frames to see if the user opened settings dialogs (right-click menus or properties windows).
    
    Output JSON:
    {
      "hr_range_correct": boolean,
      "spo2_range_correct": boolean,
      "art_range_correct": boolean,
      "settings_dialog_seen": boolean,
      "observed_hr_values": "string describing numbers seen on HR axis",
      "observed_spo2_values": "string describing numbers seen on SpO2 axis",
      "observed_art_values": "string describing numbers seen on ART axis"
    }
    """

    vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_response.get("success"):
        analysis = vlm_response.get("parsed", {})
        
        # Scoring logic
        if analysis.get("hr_range_correct"):
            score += 20
            feedback_parts.append("✅ HR range set to 40-160")
        else:
            feedback_parts.append(f"❌ HR range incorrect (Seen: {analysis.get('observed_hr_values', 'N/A')})")

        if analysis.get("spo2_range_correct"):
            score += 20
            feedback_parts.append("✅ SpO2 range set to 85-100")
        else:
            feedback_parts.append(f"❌ SpO2 range incorrect (Seen: {analysis.get('observed_spo2_values', 'N/A')})")

        if analysis.get("art_range_correct"):
            score += 20
            feedback_parts.append("✅ ART range set to 30-200")
        else:
            feedback_parts.append(f"❌ ART range incorrect (Seen: {analysis.get('observed_art_values', 'N/A')})")
            
        if analysis.get("settings_dialog_seen"):
            # Bonus/Verification that they didn't just magic it (though practically impossible to magic)
            pass 
    else:
        feedback_parts.append("⚠️ VLM analysis failed, cannot verify visual settings")

    # Pass condition
    passed = score >= 80  # Requires file + 3 correct ranges (20+20+20+20)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }