#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_pedestrian_mode(traj, env_info, task_info):
    """
    Verifies that the agent switched Sygic GPS to Pedestrian mode.
    
    Strategy:
    1. VLM Analysis of Trajectory: Did the agent go to settings -> vehicle profile?
    2. VLM Analysis of Final State: Does the map show a pedestrian icon?
    3. Programmatic Check (Bonus): Did we detect 'pedestrian' in shared prefs dump?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []

    # Criterion 1: App must be running (10 pts)
    if result_data.get("app_running", False):
        score += 10
    else:
        return {"passed": False, "score": 0, "feedback": "Sygic app was closed at the end of the task."}

    # Criterion 2: Shared Prefs Check (Secondary Signal) (10 pts)
    # If we see 'pedestrian' in the dumped prefs, that's a good sign, though prefs might not flush immediately.
    prefs_snippet = result_data.get("prefs_snippet", "").lower()
    if "pedestrian" in prefs_snippet:
        score += 10
        feedback_parts.append("System logs confirm pedestrian mode setting.")
    
    # Criterion 3: VLM Verification (80 pts)
    # We check the trajectory for the workflow and the final screen for the icon.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for workflow verification
    workflow_prompt = """
    Analyze this sequence of screenshots from the Sygic GPS Navigation app.
    The user is supposed to switch the vehicle profile from Car to Pedestrian.
    
    Look for:
    1. The Settings menu being opened.
    2. A screen showing 'Vehicle profile' or 'Route settings'.
    3. A selection menu with options like 'Car', 'Pedestrian', 'Truck'.
    4. The 'Pedestrian' option being selected.
    
    Does the sequence show the agent navigating to vehicle settings?
    """
    
    # Prompt for final state verification
    final_prompt = """
    Analyze this final screenshot of the Sygic GPS Navigation map.
    Look at the current position arrow/icon (usually in the center or bottom center).
    
    1. Is it a blue arrow (Car mode)?
    2. Is it a person/walker icon (Pedestrian mode)?
    3. Does the UI show walking/pedestrian symbols (e.g. footprints)?
    
    Answer YES if the visual evidence suggests Pedestrian mode is active. Answer NO otherwise.
    """

    # Query VLM
    try:
        workflow_result = query_vlm(images=frames, prompt=workflow_prompt).get("parsed", {})
        final_result = query_vlm(images=[final_screen], prompt=final_prompt).get("parsed", {})
        
        # We need to interpret the VLM's text response since query_vlm might return a dict or string
        # Assuming query_vlm returns a structured analysis or we parse the boolean intent.
        # Note: The standard gym_anything query_vlm often returns a dict with 'success' and 'response'.
        # For this implementation, I will assume a helper that returns boolean confidence or check specific keywords.
        
        # Re-query with specific JSON prompt for robust parsing if needed, but assuming standard VLM behavior:
        # Let's do a combined query for robust scoring.
        
        combined_prompt = """
        You are verifying a task in Sygic GPS Navigation.
        Goal: Switch to Pedestrian Mode.
        
        Input: A sequence of 4 steps + Final Screenshot.
        
        Checklist:
        1. [Workflow] Did the user enter Settings?
        2. [Workflow] Did the user select 'Pedestrian' in a menu?
        3. [Final] Does the map show a Pedestrian icon (walker) instead of a Car arrow?
        
        Respond in JSON:
        {
            "entered_settings": boolean,
            "selected_pedestrian": boolean,
            "final_icon_is_pedestrian": boolean,
            "confidence": float (0.0 to 1.0)
        }
        """
        
        vlm_resp = query_vlm(images=frames + [final_screen], prompt=combined_prompt)
        analysis = vlm_resp.get("parsed", {})
        
        if not analysis:
             # Fallback if parsing failed
             feedback_parts.append("VLM analysis failed to parse.")
        else:
            if analysis.get("entered_settings"):
                score += 20
                feedback_parts.append("Correctly navigated to settings.")
            
            if analysis.get("selected_pedestrian"):
                score += 30
                feedback_parts.append("Selected 'Pedestrian' option.")
                
            if analysis.get("final_icon_is_pedestrian"):
                score += 30
                feedback_parts.append("Final map shows Pedestrian icon.")
            
    except Exception as e:
        feedback_parts.append(f"VLM verification error: {str(e)}")

    # Pass Threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }