#!/usr/bin/env python3
"""
Verifier for view_ifr_low_chart task.

Verifies:
1. Agent downloaded IFR Low chart data (File check).
2. Agent switched display to IFR Low chart (VLM check).
3. Agent saved a confirmation screenshot (File check).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_view_ifr_low_chart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve Artifacts
    # ================================================================
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    agent_screenshot_path = os.path.join(temp_dir, "ifr_chart_result.png")
    
    try:
        copy_from_env("/sdcard/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    # Try to get agent's specific screenshot if it exists
    has_agent_screenshot = False
    if result_data.get("agent_screenshot_exists", False):
        try:
            copy_from_env("/sdcard/ifr_chart_result.png", agent_screenshot_path)
            has_agent_screenshot = True
        except:
            pass

    # ================================================================
    # 2. VLM Verification (Visual State)
    # ================================================================
    # We use the system-captured final screenshot from trajectory for truth
    # AND the agent's screenshot if available to give points for following instructions.
    
    final_frame = get_final_screenshot(traj)
    if not final_frame and has_agent_screenshot:
        # Fallback to agent screenshot if trajectory is missing (rare)
        import cv2
        final_frame = cv2.imread(agent_screenshot_path)

    vlm_score = 0
    vlm_feedback = ""
    
    if final_frame is not None:
        prompt = """
        You are an aviation chart expert. Look at this screenshot from an EFB (Electronic Flight Bag).
        
        Determine the type of chart displayed:
        1. Is it a 'Sectional' chart? (Colorful terrain, yellow city blobs, dense topographical detail)
        2. Is it an 'IFR Enroute Low' chart? (Mostly white background, blue or brown lines for airways e.g., 'V107', intersection triangles, sparse terrain info)
        
        Task requirement: The user must switch the map to 'IFR Low'.
        
        Respond in JSON:
        {
            "chart_type": "IFR_Low" or "Sectional" or "Unknown",
            "is_ifr_visible": true/false,
            "reasoning": "..."
        }
        """
        
        vlm_resp = query_vlm(
            prompt=prompt,
            image=final_frame
        )
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("is_ifr_visible", False) or parsed.get("chart_type") == "IFR_Low":
                vlm_score = 50
                vlm_feedback = "VLM confirmed IFR Low chart is displayed."
            else:
                vlm_feedback = f"VLM saw {parsed.get('chart_type')}. Expected IFR Low chart."
        else:
            vlm_feedback = "VLM analysis failed."
    else:
        vlm_feedback = "No screenshots available for analysis."

    # ================================================================
    # 3. File System Verification (Data Download)
    # ================================================================
    files_added = result_data.get("files_added_count", 0)
    ifr_detected = result_data.get("ifr_files_detected", False)
    
    data_score = 0
    data_feedback = ""
    
    if files_added > 0:
        if ifr_detected:
            data_score = 30
            data_feedback = "New IFR chart files detected in storage."
        else:
            # Maybe they downloaded it but the grep didn't catch specific keywords
            # but files were added. Give partial credit.
            data_score = 15
            data_feedback = "New files added, but specific IFR naming not confirmed."
    else:
        data_feedback = "No new chart data found on disk."

    # ================================================================
    # 4. Agent Evidence Verification
    # ================================================================
    evidence_score = 0
    if has_agent_screenshot:
        evidence_score = 20
        evidence_feedback = "Agent saved requested screenshot."
    else:
        evidence_feedback = "Agent did not save result screenshot to /sdcard/ifr_chart_result.png."

    # ================================================================
    # Scoring
    # ================================================================
    total_score = vlm_score + data_score + evidence_score
    passed = total_score >= 80
    
    full_feedback = f"{vlm_feedback} {data_feedback} {evidence_feedback}"
    
    # Cleanup
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": full_feedback
    }