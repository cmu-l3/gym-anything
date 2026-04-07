#!/usr/bin/env python3
"""
Verifier for metal_stamping_tonnage_logic task.

Uses a multi-signal approach combining binary-dump text parsing and 
Vision Language Model (VLM) trajectory checks to securely verify formulas in 
proprietary Red Lion .c3 binary files.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_metal_stamping_tonnage_logic(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Fetch JSON Result from Container Environment
    json_path = "C:\\Users\\Docker\\Desktop\\CrimsonTasks\\metal_stamping_result.json"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()

    result = {}
    try:
        copy_from_env(json_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # 2. Programmatic Gate Checks
    if not result.get("project_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAILED: 'press_tonnage.c3' was not found. Agent did not save the project."
        }

    score = 0
    feedback_parts = []
    
    if not result.get("file_created_during_task"):
        feedback_parts.append("[Warning] Project file was not created/modified during the active task window.")

    # 3. Binary String Analysis (30 points)
    # Verifies presence of tags via raw string dump from the .c3 binary format
    raw_text = result.get("raw_text_dump", "")
    base_tags = ["LC_LF", "LC_RF", "LC_LR", "LC_RR"]
    
    base_tags_found = all(tag in raw_text for tag in base_tags)
    calc_tags_found = all(tag in raw_text for tag in ["Total_Tonnage", "Imbalance_LR", "Imbalance_FR"])
    abs_func_found = "abs(" in raw_text.lower()

    if base_tags_found:
        score += 15
        feedback_parts.append("Base load cell tags found in binary stream.")
    else:
        feedback_parts.append("Base load cell tags missing from project file.")

    if calc_tags_found:
        score += 10
        feedback_parts.append("Calculated tag names found in binary stream.")

    if abs_func_found:
        score += 5
        feedback_parts.append("Mathematical function 'abs()' found in binary stream.")

    # 4. VLM Trajectory Verification (70 points)
    # Required to securely verify formula syntax and GUI alarms since .c3 is proprietary
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            prompt = """Analyze these screenshots of a Red Lion Crimson 3.0 session carefully.
The user was tasked with creating tags for a metal press tonnage monitor. Look specifically at the Data Tags pane.

Evaluate the following criteria:
1. Base Tags: Are the 4 base load cell tags (LC_LF, LC_RF, LC_LR, LC_RR) created with the correct unit (Tons)?
2. Total_Tonnage: Is there a 'Total_Tonnage' tag configured with a 'General...' Source expression that adds the four load cells together?
3. Imbalance Formulas: Are there 'Imbalance_LR' and 'Imbalance_FR' tags using the abs() function to calculate the left-right and front-rear differences?
4. Alarms: Are High (100, 80) and High-High (150, 120) alarms configured for the Imbalance tags?

Respond strictly in valid JSON format:
{
  "base_tags_configured": true/false,
  "total_tonnage_logic": true/false,
  "imbalance_formulas_correct": true/false,
  "alarms_configured": true/false,
  "confidence": "high/medium/low",
  "observations": "brief summary of what is visible"
}"""
            vlm_resp = query_vlm(images=images, prompt=prompt)

            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("base_tags_configured"):
                    vlm_score += 10
                if parsed.get("total_tonnage_logic"):
                    vlm_score += 20
                    feedback_parts.append("VLM verified Total_Tonnage sum formula.")
                if parsed.get("imbalance_formulas_correct"):
                    vlm_score += 25
                    feedback_parts.append("VLM verified Imbalance formulas correctly leverage abs().")
                if parsed.get("alarms_configured"):
                    vlm_score += 15
                    feedback_parts.append("VLM verified correct High/High-High Imbalance alarms.")
            else:
                feedback_parts.append("VLM verification failed to parse.")
        except Exception as e:
            logger.error(f"VLM verification exception: {e}")
            feedback_parts.append(f"VLM visual trajectory verification error: {e}")
    else:
        feedback_parts.append("VLM not available, cannot visually verify logic and alarms.")

    score += vlm_score

    # Determine final output status
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "base_tags_found_in_binary": base_tags_found,
            "calc_tags_found_in_binary": calc_tags_found,
            "vlm_score": vlm_score
        }
    }