#!/usr/bin/env python3
"""
Verifier for analyze_part_mass task.

Verification Strategy (Multi-Criteria):
1. Programmatic: side_extruded.slvs exists and was created during the task.
2. Programmatic: side_extruded.slvs has more groups than side.slvs (proves extrusion/modification).
3. Programmatic: mass_report.txt exists and contains a numeric value.
4. VLM: Analyzes trajectory to confirm the "Analyze -> Volume" window was used.
5. VLM: Confirms the reported mass is mathematically accurate (Volume * 0.0027).
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a CAD engineering task. 
The agent was asked to:
1. Extrude a 2D sketch by exactly 5.0 mm in SolveSpace.
2. Open the 'Analyze -> Volume' tool window.
3. Find the volume (in mm³) and calculate the mass (Volume * 0.0027 g/mm³).
4. Save the mass in a text file.

The agent's text file contained the following content:
"{report_content}"

Review the provided screenshots (trajectory + final state) and determine:
1. Did the agent successfully extrude the sketch into a 3D solid?
2. Is there a frame where the 'Volume' or 'Area' analysis text window is open?
3. Can you find the calculated Volume in mm³ on the screen?
4. Does the numeric value in the agent's text file logically equal the screen's Volume multiplied by 0.0027 (allow small rounding errors)?

Respond ONLY in valid JSON format:
{
    "extrusion_visible": true/false,
    "volume_window_opened": true/false,
    "calculation_correct": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_analyze_part_mass(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load programmatic results
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

    task_start = result.get("task_start", 0)
    score = 0
    feedback = []

    # 1. Extruded File Verification (20 pts)
    extruded_exists = result.get("extruded_exists", False)
    extruded_mtime = result.get("extruded_mtime", 0)
    
    if extruded_exists and extruded_mtime >= task_start:
        score += 20
        feedback.append("✅ Extruded file saved correctly.")
    elif extruded_exists:
        feedback.append("❌ Extruded file exists but has old timestamp (gaming attempt).")
    else:
        feedback.append("❌ Extruded file not found.")

    # 2. Extrusion Group Verification (20 pts)
    old_groups = result.get("old_groups", 0)
    new_groups = result.get("new_groups", 0)
    
    if new_groups > old_groups:
        score += 20
        feedback.append("✅ New group added (extrusion confirmed).")
    else:
        feedback.append("❌ No new groups added to the model.")

    # 3. Report File Verification (10 pts)
    report_exists = result.get("report_exists", False)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "")
    
    if report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("✅ Report file saved correctly.")
    else:
        feedback.append("❌ Report file missing or old.")

    # 4. Report Content Numeric Check (10 pts)
    numbers_found = re.findall(r"[-+]?\d*\.\d+|\d+", str(report_content))
    if numbers_found:
        score += 10
        feedback.append(f"✅ Found numeric values in report: {numbers_found[0]}")
    else:
        feedback.append("❌ No numeric value found in the report.")

    # 5. VLM Verification (40 pts)
    vlm_score = 0
    if query_vlm and report_exists:
        try:
            frames = sample_trajectory_frames(traj, n=6)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames
            
            prompt = VLM_PROMPT.format(report_content=report_content)
            vlm_response = query_vlm(prompt=prompt, images=images)
            
            if vlm_response and vlm_response.get("success"):
                vlm_data = vlm_response.get("parsed", {})
                
                if vlm_data.get("extrusion_visible"):
                    vlm_score += 10
                if vlm_data.get("volume_window_opened"):
                    vlm_score += 10
                    feedback.append("✅ VLM confirmed Volume window was opened.")
                if vlm_data.get("calculation_correct"):
                    vlm_score += 20
                    feedback.append("✅ VLM confirmed mass calculation is mathematically correct.")
                else:
                    feedback.append(f"⚠️ VLM check on math calculation: {vlm_data.get('reasoning', 'Incorrect')}")
            else:
                feedback.append("⚠️ VLM request failed.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback.append("⚠️ VLM evaluation encountered an error.")
    else:
        feedback.append("⚠️ Skipping VLM verification (Not available or no report).")
    
    score += vlm_score

    # Determine Pass/Fail (Requires good score AND file creation)
    passed = score >= 75 and extruded_exists and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "programmatic_score": score - vlm_score,
            "vlm_score": vlm_score,
            "report_content": report_content
        }
    }