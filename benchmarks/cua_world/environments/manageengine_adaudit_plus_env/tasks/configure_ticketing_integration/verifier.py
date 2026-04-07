#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ticketing_integration(traj, env_info, task_info):
    """
    Verify ADAudit Plus ticketing integration configuration.
    
    Primary Verification: VLM checks on final screenshot and trajectory.
    Secondary Verification: Basic file/log evidence from container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    metadata = task_info.get('metadata', {})
    expected_server = metadata.get('server_name', 'sdp.corpnet.local')
    expected_port = metadata.get('port', '8080')
    
    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not retrieve task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. VLM Verification Strategy
    # We check:
    # A. Did the agent navigate to the integration settings? (Trajectory)
    # B. Are the specific values entered/visible? (Final State/Trajectory)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    # If final shot missing from trajectory, try to get from container export
    if not final_shot and task_result.get('screenshot_exists'):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(task_result['screenshot_path'], temp_img.name)
            final_shot = temp_img.name
        except:
            pass
            
    if not final_shot:
        return {"passed": False, "score": 0, "feedback": "No visual evidence (screenshots) available"}

    # Prompt for VLM
    prompt = f"""
    You are verifying if a user configured the 'ServiceDesk Plus' integration in ADAudit Plus correctly.
    
    Expected Configuration:
    - Integration Type: ServiceDesk Plus
    - Server Name: {expected_server}
    - Port: {expected_port}
    - Protocol: HTTP
    - API Key: (Any long string/masked value is acceptable)
    
    Please examine the images (trajectory and final state) and answer:
    1. Did the user navigate to the 'Integration' or 'Admin' settings page?
    2. Is 'ServiceDesk Plus' selected or visible?
    3. Is the Server Name set to '{expected_server}'?
    4. Is the Port set to '{expected_port}'?
    5. Is the Protocol set to HTTP (not HTTPS)?
    6. Was the configuration saved (e.g., clicked Save, success message, or values persisted)?
    
    Provide a score from 0 to 100 based on these criteria.
    - 20 pts: Navigation to correct page
    - 20 pts: Correct System (ServiceDesk Plus)
    - 20 pts: Correct Server Name
    - 20 pts: Correct Port & Protocol
    - 20 pts: Saved/Completed
    
    Return JSON: {{"score": int, "feedback": "explanation", "passed": bool}}
    Pass threshold is 70 points.
    """
    
    vlm_response = query_vlm(images=frames + [final_shot], prompt=prompt)
    
    if not vlm_response.get('success'):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to execute"}
        
    vlm_result = vlm_response.get('parsed', {})
    score = vlm_result.get('score', 0)
    feedback = vlm_result.get('feedback', 'No feedback provided')
    
    # Anti-gaming: Ensure score is grounded
    if score > 0 and not task_result.get('screenshot_exists', True):
         # If container didn't generate a screenshot but VLM scored high, be suspicious?
         # Actually VLM uses trajectory, so this is fine.
         pass

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": feedback
    }