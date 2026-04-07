#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def verify_monitor_mu_rhythm(traj, env_info, task_info):
    """
    Verifies the Monitor Mu Rhythm task using VLM analysis of the trajectory
    and file system checks.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: Missing verification tools"}

    # Load JSON result from container
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Initialization
    score = 0
    feedback = []
    
    # 3. File & System Checks (20 points max)
    # Screenshot saved to correct path?
    if task_result.get("agent_screenshot_exists") and task_result.get("agent_screenshot_created_during_task"):
        score += 10
        feedback.append("Success: Agent saved screenshot to correct path.")
    elif task_result.get("agent_screenshot_exists"):
        score += 5
        feedback.append("Partial: Screenshot exists but timestamp is old/suspicious.")
    else:
        feedback.append("Fail: No screenshot saved to ~/Documents/OpenBCI_GUI/Screenshots/.")

    # App running?
    if task_result.get("app_running"):
        score += 10
        feedback.append("Success: OpenBCI GUI is running.")
    else:
        feedback.append("Fail: OpenBCI GUI was closed.")

    # 4. VLM Verification (80 points max)
    # We analyze the final state primarily, but check trajectory if final is ambiguous
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if final_frame is None:
        return {"passed": False, "score": score, "feedback": " ".join(feedback) + " No video evidence found."}
        
    # Construct VLM Prompt
    prompt = """
    Analyze this sequence of screenshots from the OpenBCI GUI. The user is performing a monitoring task.
    
    Please check for the following SPECIFIC criteria:
    1. **Playback Mode**: Is the data source set to 'PLAYBACK' (or 'File')? Is a file named '...MotorImagery.txt' loaded or visible?
    2. **Band Power Widget**: Is the 'Band Power' widget visible in the layout? (It shows bar charts for Delta, Theta, Alpha, Beta, Gamma).
    3. **Channel Isolation**: Are exactly TWO channels active/visible in the Band Power widget? (i.e., you see data bars for only 2 rows, or other rows are flat/greyed out).
    4. **Specific Channels**: Do the active channels appear to be Channel 3 and Channel 4? (Look for channel numbers 3 and 4, or labels like C3/C4).
    
    Report in JSON format:
    {
        "playback_mode_confirmed": boolean,
        "band_power_widget_visible": boolean,
        "two_channels_only": boolean,
        "channels_3_and_4_confirmed": boolean,
        "reasoning": "string"
    }
    """
    
    try:
        # We send the last few frames + final frame to give context
        analysis_images = frames[-2:] + [final_frame]
        vlm_response = query_vlm(images=analysis_images, prompt=prompt)
        
        # Parse VLM output (handling potential markdown wrapping)
        content = vlm_response.get('result', '{}')
        if "