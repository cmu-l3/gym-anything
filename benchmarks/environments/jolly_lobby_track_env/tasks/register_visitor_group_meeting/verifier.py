#!/usr/bin/env python3
"""
Verifier for register_visitor_group_meeting task.

Strategy:
1. Verify agent saved the requested screenshot (anti-gaming check).
2. Use VLM to analyze TRAJECTORY frames to confirm the workflow (3 distinct registrations).
3. Use VLM to analyze FINAL state (visitor log) to confirm names/host/purpose.
"""

import json
import tempfile
import os
import logging
import time
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_visitor_group_meeting(traj, env_info, task_info):
    """
    Verifies that 3 visitors were registered correctly for the board meeting.
    """
    # 1. Setup & Read Export Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    visitors = metadata.get('visitors', [])
    common_details = metadata.get('common_details', {})
    
    # Load exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # =========================================================
    # CRITERION 1: File Artifact Verification (5 points)
    # =========================================================
    if export_result.get('agent_screenshot_valid', False):
        score += 5
        feedback_parts.append("✅ Screenshot saved correctly.")
    elif export_result.get('agent_screenshot_exists', False):
        feedback_parts.append("⚠️ Screenshot exists but has wrong timestamp (pre-dated?).")
    else:
        feedback_parts.append("❌ Agent failed to save the screenshot to /tmp/visitor_log_screenshot.png.")

    # =========================================================
    # CRITERION 2: VLM Trajectory Verification (Workflow) (45 points)
    # Did the agent actually perform the registration steps?
    # =========================================================
    
    # Sample frames from the middle of the task to catch the form filling
    traj_frames = sample_trajectory_frames(traj, n=8)
    
    workflow_prompt = """
    Analyze these screenshots of a visitor management software (Lobby Track).
    I am looking for evidence that the user registered THREE different visitors.
    
    Look for data entry forms being filled with these specific names:
    1. Margaret Chen
    2. David Okonkwo
    3. Susan Lindqvist
    
    And the host "Patricia Alvarez".
    
    Output JSON:
    {
        "margaret_seen": boolean,
        "david_seen": boolean,
        "susan_seen": boolean,
        "host_patricia_seen": boolean,
        "purpose_board_meeting_seen": boolean,
        "distinct_registrations_count": number (0-3)
    }
    """
    
    # We query the VLM with the trajectory frames
    workflow_result = query_vlm(
        images=traj_frames,
        prompt=workflow_prompt
    )
    
    workflow_data = workflow_result.get('parsed', {})
    
    # Score workflow
    w_score = 0
    if workflow_data.get('margaret_seen'): w_score += 10
    if workflow_data.get('david_seen'): w_score += 10
    if workflow_data.get('susan_seen'): w_score += 10
    if workflow_data.get('host_patricia_seen'): w_score += 10
    if workflow_data.get('purpose_board_meeting_seen'): w_score += 5
    
    score += w_score
    feedback_parts.append(f"Workflow Analysis: Found {workflow_data.get('distinct_registrations_count', 0)}/3 registration actions.")

    # =========================================================
    # CRITERION 3: Final State Verification (Log Check) (50 points)
    # Does the final screenshot show the visitors in the log?
    # =========================================================
    
    # Use the system screenshot as ground truth if available, otherwise try agent screenshot
    # We need to get the image data. In this environment, we rely on the framework's 
    # 'get_final_screenshot' which gets the last frame of the trajectory.
    final_image = get_final_screenshot(traj)
    
    if final_image:
        log_prompt = """
        Examine this screenshot of the Visitor Log / Active Visitors list.
        
        Check for the presence of these specific rows:
        1. Visitor: Margaret Chen | Company: Apex Capital
        2. Visitor: David Okonkwo | Company: Riverton Financial
        3. Visitor: Susan Lindqvist | Company: Nordic Ventures
        
        Check if the Host is "Patricia Alvarez" and Purpose is "Board Meeting" for them.
        
        Output JSON:
        {
            "visitors_present": ["list", "of", "names", "found"],
            "host_correct": boolean,
            "purpose_correct": boolean,
            "all_three_visible": boolean
        }
        """
        
        log_result = query_vlm(
            images=[final_image],
            prompt=log_prompt
        )
        
        log_data = log_result.get('parsed', {})
        found_visitors = log_data.get('visitors_present', [])
        
        # Scoring based on what's visible in the final log
        log_score = 0
        
        # Check for each name in the VLM's found list (fuzzy matching handled by VLM usually, but we check strings)
        found_count = 0
        found_names = [n.lower() for n in found_visitors]
        
        if any("margaret" in n or "chen" in n for n in found_names): 
            log_score += 10
            found_count += 1
        if any("david" in n or "okonkwo" in n for n in found_names): 
            log_score += 10
            found_count += 1
        if any("susan" in n or "lindqvist" in n for n in found_names): 
            log_score += 10
            found_count += 1
            
        if log_data.get('host_correct'): log_score += 10
        if log_data.get('purpose_correct'): log_score += 10
        
        score += log_score
        feedback_parts.append(f"Final Log Analysis: Found {found_count}/3 visitors in the active log.")
        if log_data.get('host_correct'): feedback_parts.append("✅ Host verified in log.")
        if log_data.get('purpose_correct'): feedback_parts.append("✅ Purpose verified in log.")
        
    else:
        feedback_parts.append("❌ No final screenshot available for log verification.")

    # =========================================================
    # Final Result
    # =========================================================
    
    # Pass threshold: 60 points (Requires at least 2 visitors fully registered and visible)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }