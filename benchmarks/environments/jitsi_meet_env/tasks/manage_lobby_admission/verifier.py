#!/usr/bin/env python3
"""
Verifier for manage_lobby_admission@1.

Verification Strategy:
1. Process Check: Verify both Firefox (Host) and Epiphany (Guest) are running.
2. Log Analysis: Check Jitsi server logs for evidence of Lobby enabling/Room creation.
3. VLM Trajectory: Confirm the workflow (Enable Lobby -> Guest Join -> Admit).
4. VLM Final State: Confirm two participants are visible in the meeting.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_lobby_admission(traj, env_info, task_info):
    """
    Verify the agent managed the lobby admission correctly.
    """
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Metadata
    metadata = task_info.get('metadata', {})
    room_name = metadata.get('room_name', 'HR_Interview_Confidential')
    guest_name = metadata.get('guest_name', 'Jane_Doe_Candidate')

    # 3. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Process Health (20 pts) ---
    firefox_running = result.get('firefox_running', False)
    epiphany_running = result.get('epiphany_running', False)
    
    if firefox_running:
        score += 10
    if epiphany_running:
        score += 10
        feedback_parts.append("Both browsers running")
    else:
        feedback_parts.append("Guest browser (Epiphany) NOT running")

    # --- Criterion 2: Server Log Evidence (10 pts) ---
    # We check if the room was touched or lobby enabled in logs
    log_lobby = result.get('log_lobby_evidence', '')
    log_room = result.get('log_room_evidence', '')
    
    if log_room:
        score += 5 # Room was definitely active
    if log_lobby:
        score += 5
        feedback_parts.append("Lobby activation detected in logs")
    
    # --- Criterion 3: VLM Workflow Verification (70 pts) ---
    # We need to verify the specific interaction: Enabling Lobby -> Guest waiting -> Admitting
    
    frames = sample_trajectory_frames(traj, n=6)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        return {"passed": False, "score": score, "feedback": "No visual evidence available"}

    # Prompt for VLM
    prompt = f"""
    You are verifying a Jitsi Meet task where the user must:
    1. Host a meeting in Firefox (Room: {room_name})
    2. Enable 'Lobby Mode' in Security settings
    3. Join as a guest '{guest_name}' in a DIFFERENT browser (Epiphany)
    4. Admit the guest from the Host browser.
    
    Review the sequence of images and the final state.
    
    Check for:
    - TWO distinct browser windows visible at some point (Firefox + Epiphany).
    - The 'Security' or 'Lobby' settings menu being accessed.
    - A notification about a participant 'Knocking' or 'Asking to join'.
    - The participant list in the FINAL image showing TWO people (Host + Guest).
    - The Guest name '{guest_name}' visible in the participant list or video tile.
    
    Return JSON:
    {{
        "two_browsers_seen": boolean,
        "lobby_settings_accessed": boolean,
        "knocking_notification_seen": boolean,
        "guest_admitted": boolean,
        "guest_name_visible": boolean,
        "final_participant_count_is_two": boolean
    }}
    """
    
    vlm_result = query_vlm(images=frames + [final_shot], prompt=prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        # Scoring logic based on VLM
        if parsed.get('two_browsers_seen'):
            score += 10
        if parsed.get('lobby_settings_accessed'):
            score += 10
        if parsed.get('knocking_notification_seen'):
            score += 10
        if parsed.get('guest_admitted'):
            score += 20
        if parsed.get('final_participant_count_is_two'):
            score += 20 # Strong confirmation
            
        if not parsed.get('guest_admitted') and not parsed.get('final_participant_count_is_two'):
            feedback_parts.append("Failed to verify guest admission visually")
    else:
        feedback_parts.append("VLM analysis failed")

    # Final Pass/Fail
    # Need significant score (>= 70) AND guest admission confirmation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }