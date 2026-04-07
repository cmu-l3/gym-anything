#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ganglion_dashboard(traj, env_info, task_info):
    """
    Verify the configuration of the Ganglion Multimodal Dashboard task.
    
    Criteria:
    1. Agent screenshot exists and was created during task (anti-gaming).
    2. VLM confirms Ganglion mode (4 channels) from screenshot.
    3. VLM confirms presence of Time Series, FFT, Band Power, and EMG widgets.
    4. VLM confirms 4-pane layout.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available"}

    # 1. Retrieve JSON result from container
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Agent's Screenshot (if it exists)
    agent_screenshot_path = None
    if task_result.get("screenshot_exists") and task_result.get("file_created_during_task"):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/agent_screenshot.png", temp_img.name)
            agent_screenshot_path = temp_img.name
        except Exception as e:
            logger.error(f"Failed to copy agent screenshot: {e}")
    
    # 3. Retrieve Trajectory Frames (for secondary verification or if screenshot missing)
    traj_frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    # Decide which image to use for primary VLM verification
    # Prefer the agent's screenshot if valid, otherwise use final frame
    verification_image = agent_screenshot_path if agent_screenshot_path else final_frame
    
    if not verification_image:
        return {"passed": False, "score": 0, "feedback": "No visual evidence available (no screenshot or trajectory)"}

    # 4. VLM Verification
    prompt = """
    Analyze this image of the OpenBCI GUI.
    
    I need to verify if the user has correctly configured a 'Ganglion' board dashboard with specific widgets.
    
    Please check the following carefully:
    1. **Channel Count (Ganglion Mode):** Count the number of distinct signal rows in the Time Series widget or bars in the Band Power widget. 
       - Ganglion has EXACTLY 4 channels.
       - Cyton has 8 channels.
       - Does the display show data for 4 channels? (Ignore the 'Accelerometers' widget if present).
    
    2. **Widget Identification:** Are the following widgets visible?
       - Time Series (waveforms scrolling)
       - FFT Plot (frequency spectrum graph)
       - Band Power (bar charts for Alpha, Beta, etc.)
       - EMG (muscle activity, usually bar graphs or rectified signals)
       
    3. **Layout:** Is the window split into approximately 4 main panels/areas?
    
    Return your response in JSON format:
    {
        "channel_count_approx": <number, e.g. 4, 8, 16>,
        "is_ganglion_4ch": <true/false>,
        "widgets_visible": {
            "time_series": <true/false>,
            "fft": <true/false>,
            "band_power": <true/false>,
            "emg": <true/false>
        },
        "layout_is_multi_pane": <true/false>,
        "data_is_streaming": <true/false, based on non-flat lines>
    }
    """
    
    vlm_response = query_vlm(images=[verification_image], prompt=prompt)
    
    # Clean up temp image
    if agent_screenshot_path and os.path.exists(agent_screenshot_path):
        os.unlink(agent_screenshot_path)
        
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM analysis failed: {vlm_response.get('error')}"}
        
    analysis = vlm_response.get("parsed", {})
    
    # 5. Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: Screenshot exists and created during task (10 pts)
    if task_result.get("screenshot_exists") and task_result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("Screenshot saved correctly.")
    else:
        feedback_parts.append("Screenshot missing or old.")

    # Criterion 2: Ganglion Mode / 4 Channels (20 pts)
    if analysis.get("is_ganglion_4ch") or analysis.get("channel_count_approx") == 4:
        score += 20
        feedback_parts.append("Ganglion mode (4ch) confirmed.")
    elif analysis.get("channel_count_approx") == 8:
        feedback_parts.append("Incorrect board: Looks like Cyton (8ch).")
    else:
        feedback_parts.append(f"Channel count unclear ({analysis.get('channel_count_approx')}).")

    # Criterion 3: Widgets (15 pts each, max 60)
    widgets = analysis.get("widgets_visible", {})
    
    if widgets.get("time_series"):
        score += 15
        feedback_parts.append("Time Series active.")
    else:
        feedback_parts.append("Time Series missing.")
        
    if widgets.get("fft"):
        score += 15
        feedback_parts.append("FFT active.")
    else:
        feedback_parts.append("FFT missing.")
        
    if widgets.get("band_power"):
        score += 15
        feedback_parts.append("Band Power active.")
    else:
        feedback_parts.append("Band Power missing.")
        
    if widgets.get("emg"):
        score += 15
        feedback_parts.append("EMG active.")
    else:
        feedback_parts.append("EMG missing.")

    # Criterion 4: Layout (10 pts)
    if analysis.get("layout_is_multi_pane"):
        score += 10
        feedback_parts.append("Layout correct.")
    
    # Pass threshold: 70 points AND Ganglion mode must be correct
    passed = (score >= 70) and (analysis.get("is_ganglion_4ch") or analysis.get("channel_count_approx") == 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }