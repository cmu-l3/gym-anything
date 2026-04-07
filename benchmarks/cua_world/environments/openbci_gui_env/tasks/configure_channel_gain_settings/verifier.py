#!/usr/bin/env python3
"""
Verifier for configure_channel_gain_settings task.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_channel_gain_settings(traj, env_info, task_info):
    """
    Verifies that the agent configured the OpenBCI GUI channel gains correctly.
    
    Verification Signals:
    1. Application State: OpenBCI GUI must be running.
    2. File Evidence: 
       - Report file exists and contains correct mappings (Channels 1-8).
       - Screenshot file exists.
    3. VLM Verification:
       - Checks trajectory/final screenshot for Hardware Settings panel visibility.
       - confirm gain values if visible.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_gains = metadata.get('gains', {})

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Process Check (10 pts)
    # ------------------------------------------------------------------
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI is NOT running.")

    # ------------------------------------------------------------------
    # 2. Report File Verification (40 pts)
    # ------------------------------------------------------------------
    report = result.get('report_file', {})
    if report.get('exists') and report.get('created_during_task'):
        content = report.get('content', '')
        
        # Check specific gain values in the text report
        correct_channels = 0
        total_channels = 8
        
        for ch_num, expected_gain in expected_gains.items():
            # Regex to find "Channel X: Y" or similar patterns
            # Matches: "Channel 1: 12x", "Ch1 12x", "1: 12"
            pattern = re.compile(rf"(?i)channel\s*0?{ch_num}.*?{expected_gain}")
            if pattern.search(content):
                correct_channels += 1
            else:
                # Fallback: check just number and gain in close proximity
                if expected_gain in content and str(ch_num) in content:
                    # Weak match, assume mostly ok if lines are separated
                    pass
        
        # Score based on correct channels reported (5 pts per channel)
        report_score = correct_channels * 5
        score += report_score
        feedback_parts.append(f"Report file confirms {correct_channels}/8 channels correctly configured.")
        
        if correct_channels < 4:
             feedback_parts.append("Report content missing or incorrect.")
    else:
        feedback_parts.append("Report file missing or not created during task.")

    # ------------------------------------------------------------------
    # 3. Screenshot File Verification (10 pts)
    # ------------------------------------------------------------------
    screenshot = result.get('agent_screenshot', {})
    if screenshot.get('exists') and screenshot.get('created_during_task'):
        score += 10
        feedback_parts.append("Agent screenshot saved successfully.")
    else:
        feedback_parts.append("Agent screenshot missing.")

    # ------------------------------------------------------------------
    # 4. VLM Verification (40 pts)
    # ------------------------------------------------------------------
    # We use trajectory to find the best view of the Hardware Settings panel
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Add final screen to check list
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    if query_vlm and images_to_check:
        prompt = """
        You are verifying an OpenBCI GUI task. 
        Look for the 'Hardware Settings' panel. It typically contains a grid of channels (1-8) with dropdowns for 'PGA Gain' (values like 24x, 12x, 8x).
        
        Task Requirements:
        - Channel 1, 2: Gain 12x
        - Channel 3, 4, 5, 6: Gain 24x
        - Channel 7, 8: Gain 8x
        
        Q1: Is the Hardware Settings panel visible in any of these images?
        Q2: Can you see the gain values set for the channels?
        Q3: do the visible gain values match the requirements above?
        
        Return JSON:
        {
            "hardware_panel_visible": boolean,
            "gains_match_requirements": boolean,
            "explanation": "string"
        }
        """
        
        vlm_response = query_vlm(images=images_to_check, prompt=prompt)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            if parsed.get("hardware_panel_visible"):
                score += 15
                feedback_parts.append("VLM confirmed Hardware Settings panel was opened.")
                
                if parsed.get("gains_match_requirements"):
                    score += 25
                    feedback_parts.append("VLM confirmed gain values match requirements visually.")
                else:
                    feedback_parts.append("VLM could not confirm all gain values matched (visual ambiguity or incorrect).")
            else:
                feedback_parts.append("VLM did not see the Hardware Settings panel in the trajectory.")
        else:
            feedback_parts.append("VLM verification failed to run.")
            # Fallback points if report was perfect, to avoid penalizing VLM outage
            if score >= 50: 
                score += 20
                feedback_parts.append("Awarding fallback points due to VLM outage.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }