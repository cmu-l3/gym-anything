#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_replace_fft_with_head_plot(traj, env_info, task_info):
    """
    Verifies that the agent replaced the FFT Plot with the Head Plot widget.
    
    Criteria:
    1. Agent screenshot exists and was created during task (anti-gaming).
    2. OpenBCI GUI is running in a session (not startup screen).
    3. Head Plot widget is visible.
    4. FFT Plot widget is NOT visible (replaced).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Load basic file-based results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_log = []
    
    # Check 1: Screenshot file existence (10 pts)
    if result.get("screenshot_exists") and result.get("screenshot_valid_time"):
        score += 10
        feedback_log.append("Screenshot saved correctly.")
    elif result.get("screenshot_exists"):
        feedback_log.append("Screenshot exists but timestamp is invalid (pre-existing file).")
    else:
        feedback_log.append("No screenshot saved.")

    # Check 2: App running (10 pts)
    if result.get("app_running"):
        score += 10
        feedback_log.append("OpenBCI GUI is running.")
    else:
        feedback_log.append("OpenBCI GUI is not running.")

    # 3. VLM Verification
    # We look at the trajectory and the final state to confirm the widget swap.
    # We use the final system screenshot for the definitive state check.
    
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
         return {"passed": False, "score": score, "feedback": "No video/screenshot evidence available."}
    
    # Prepare VLM prompt
    prompt = """
    You are verifying an OpenBCI GUI task.
    Goal: The user should have replaced the 'FFT Plot' widget with the 'Head Plot' widget.
    
    Analyze the FINAL screenshot provided.
    
    1. Is the OpenBCI GUI in an active session (waveforms visible, not just the startup menu)?
    2. Do you see the 'Head Plot' widget? (It looks like a circular scalp map with colors, typically labeled 'Head Plot').
    3. Do you see the 'FFT Plot' widget? (It looks like a frequency line graph, typically labeled 'FFT Plot').
    
    Constraint: The goal is to REPLACE the FFT Plot. So Head Plot should be PRESENT, and FFT Plot should be ABSENT (or at least replaced in its primary location).
    
    Return JSON:
    {
        "session_active": boolean,
        "head_plot_visible": boolean,
        "fft_plot_visible": boolean,
        "widgets_visible": ["list", "of", "visible", "widget", "names"]
    }
    """
    
    try:
        vlm_response = query_vlm(
            prompt=prompt,
            images=[final_screen] 
        )
        
        analysis = vlm_response.get('parsed', {})
        
        # Scoring VLM results
        
        # Session Active (20 pts)
        if analysis.get("session_active", False):
            score += 20
            feedback_log.append("Session is active.")
        else:
            feedback_log.append("Session does not appear active (might still be in menu).")

        # Head Plot Visible (40 pts)
        if analysis.get("head_plot_visible", False):
            score += 40
            feedback_log.append("Head Plot widget is visible.")
        else:
            feedback_log.append("Head Plot widget NOT found.")
            
        # FFT Plot Removed (20 pts)
        # Note: If FFT is still visible, they added Head Plot but didn't replace FFT, or swapped the wrong one.
        if not analysis.get("fft_plot_visible", True): # Expect False
            score += 20
            feedback_log.append("FFT Plot widget successfully removed/replaced.")
        else:
            feedback_log.append("FFT Plot widget is still visible (should have been replaced).")
            
    except Exception as e:
        feedback_log.append(f"VLM analysis failed: {str(e)}")

    # Final Pass Determination
    # Threshold: Need 80+ points (meaning Head Plot MUST be there, Session Active, and preferably FFT gone or screenshot saved)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log)
    }