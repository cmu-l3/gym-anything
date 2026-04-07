#!/usr/bin/env python3
"""
Verifier for snapshot_critical_event task.

Criteria:
1. File Creation: Checks if C:\Users\Docker\Desktop\case_snapshot.png exists and was created during the task.
2. File Validity: Checks if it's a valid PNG and has reasonable dimensions/size.
3. VLM Trajectory: Verifies the agent actually performed the workflow (loaded file -> navigated).
4. VLM Content: Verifies the final image contains vital signs waveforms at the correct time.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_snapshot_critical_event(traj, env_info, task_info):
    """
    Verify that the user navigated to the critical event and took a snapshot.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size_kb = metadata.get('min_file_size_kb', 50)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timestamps (Anti-Gaming)
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    width = result.get('image_width', 0)
    height = result.get('image_height', 0)

    if output_exists:
        score += 15
        feedback_parts.append("Snapshot file exists.")
        
        if created_during_task:
            score += 15
            feedback_parts.append("File created during task.")
        else:
            feedback_parts.append("WARNING: File timestamp predates task.")

        if file_size > (min_size_kb * 1024):
            score += 10
            feedback_parts.append("File size is reasonable.")
        else:
            feedback_parts.append("File is too small/empty.")

        if width >= 800 and height >= 400:
            score += 10
            feedback_parts.append(f"Image dimensions valid ({width}x{height}).")
    else:
        feedback_parts.append("Snapshot file NOT found.")

    # 3. Retrieve the User's Screenshot for VLM Verification
    # We need to copy the actual snapshot file the user created to verify its content
    user_snapshot_valid = False
    temp_snapshot = None
    if output_exists:
        temp_snapshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            # Note: Windows paths in copy_from_env might need careful handling depending on the backend,
            # but usually the standard path works if mapped correctly.
            copy_from_env("C:\\Users\\Docker\\Desktop\\case_snapshot.png", temp_snapshot.name)
            user_snapshot_valid = True
        except Exception:
            feedback_parts.append("Failed to retrieve snapshot content.")
    
    # 4. VLM Verification
    # We verify two things:
    # A. The Agent's trajectory (did they load the file and navigate?)
    # B. The Content of the snapshot they saved (is it the right waveforms?)
    
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    images_to_check = trajectory_frames
    
    # Prompt for Trajectory
    traj_prompt = """
    Review this sequence of actions in Vital Recorder.
    1. Did the user open/load a .vital file? (Look for file dialogs or track window appearing)
    2. Did the user navigate the timeline? (Look for cursor movement or time changes)
    3. Are physiological waveforms visible (red/green traces)?
    
    Return JSON: {"file_loaded": bool, "navigated": bool, "waveforms_visible": bool}
    """
    
    traj_result = query_vlm(images=images_to_check, prompt=traj_prompt)
    traj_data = traj_result.get('parsed', {})
    
    if traj_data.get('file_loaded'):
        score += 15
        feedback_parts.append("VLM: File loading confirmed.")
    if traj_data.get('navigated'):
        score += 15
        feedback_parts.append("VLM: Timeline navigation confirmed.")
    if traj_data.get('waveforms_visible'):
        score += 10
        feedback_parts.append("VLM: Waveforms visible.")

    # Prompt for Content (The saved snapshot)
    if user_snapshot_valid and temp_snapshot:
        content_prompt = """
        Analyze this medical vital signs waveform display.
        1. Does it clearly show waveform tracks (e.g. ECG, Arterial Pressure)?
        2. Is the timeline positioned roughly around 30 minutes (00:30:xx)?
        3. Is this a valid screen capture of Vital Recorder?
        
        Return JSON: {"valid_snapshot": bool, "shows_waveforms": bool, "time_approx_30min": bool}
        """
        content_result = query_vlm(image=temp_snapshot.name, prompt=content_prompt)
        content_data = content_result.get('parsed', {})
        
        if content_data.get('valid_snapshot') and content_data.get('shows_waveforms'):
            score += 10
            feedback_parts.append("VLM: Snapshot content valid.")
            if content_data.get('time_approx_30min'):
                score += 10
                feedback_parts.append("VLM: Timepoint matches goal (~30min).")
            else:
                feedback_parts.append("VLM: Timepoint might be incorrect.")
        else:
            feedback_parts.append("VLM: Snapshot does not show valid waveforms.")
            
        # Clean up
        try:
            os.unlink(temp_snapshot.name)
        except:
            pass

    # Final decision
    # Must have the file AND meaningful VLM confirmation
    passed = (output_exists and created_during_task and score >= 60)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }