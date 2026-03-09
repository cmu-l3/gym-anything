#!/usr/bin/env python3
import json
import os
import base64
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_shortcuts_guide(traj, env_info, task_info):
    """
    Verifies the create_shortcuts_guide task.
    
    Criteria:
    1. Reference text file exists and was created during task.
    2. Reference text file contains correct shortcuts for Mute (M), Camera (V), Filmstrip (F).
    3. Evidence screenshot exists and shows the Keyboard Shortcuts overlay (VLM).
    4. Trajectory shows agent joined meeting (VLM).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load exported result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check Reference File Existence & Timing (10 pts)
    ref_exists = result.get('ref_file_exists', False)
    ref_fresh = result.get('ref_file_created_during_task', False)
    
    if ref_exists and ref_fresh:
        score += 10
        feedback_parts.append("Reference file created.")
    elif ref_exists:
        score += 5
        feedback_parts.append("Reference file exists but timestamp check failed.")
    else:
        feedback_parts.append("Reference file not found.")

    # 3. Check Reference File Content (30 pts)
    # Decode content
    content_b64 = result.get('ref_file_content_b64', "")
    try:
        content_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        content_text = ""

    # Check for shortcuts (Regex for flexibility)
    # Looking for 'M' ... 'Mute'/'Microphone', 'V' ... 'Camera'/'Video', 'F' ... 'Filmstrip'
    
    # Mute check (10 pts)
    mute_match = re.search(r'(?i)(m\b|key\s*:\s*m).*?(mute|microphone|audio)', content_text)
    if mute_match:
        score += 10
        feedback_parts.append("Mute shortcut correct.")
    else:
        feedback_parts.append("Mute shortcut missing or incorrect.")

    # Camera check (10 pts)
    cam_match = re.search(r'(?i)(v\b|key\s*:\s*v).*?(camera|video|start/stop)', content_text)
    if cam_match:
        score += 10
        feedback_parts.append("Camera shortcut correct.")
    else:
        feedback_parts.append("Camera shortcut missing or incorrect.")

    # Filmstrip check (10 pts)
    film_match = re.search(r'(?i)(f\b|key\s*:\s*f).*?(filmstrip|thumbnails|hide)', content_text)
    if film_match:
        score += 10
        feedback_parts.append("Filmstrip shortcut correct.")
    else:
        feedback_parts.append("Filmstrip shortcut missing or incorrect.")

    # 4. Check Evidence Screenshot (30 pts)
    evidence_exists = result.get('evidence_img_exists', False)
    evidence_fresh = result.get('evidence_img_created_during_task', False)
    
    if evidence_exists and evidence_fresh:
        # Pull the image for VLM analysis
        temp_evidence = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/verifier_evidence.png", temp_evidence.name)
            
            # VLM Check: Is this the shortcuts overlay?
            vlm_res = query_vlm(
                prompt="Does this screenshot show a 'Keyboard shortcuts' help overlay or modal list of keys? Look for a list of keys like 'M', 'V', 'C' and descriptions.",
                image=temp_evidence.name
            )
            
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer_bool', False): # assuming boolean parser wrapper or check result text
                # Simple text check if parser not strictly bool
                if "yes" in vlm_res.get('text', '').lower():
                    score += 30
                    feedback_parts.append("Evidence screenshot verified as Shortcuts overlay.")
                else:
                    score += 10
                    feedback_parts.append("Evidence screenshot exists but VLM did not confirm content.")
            else:
                 # Fallback if VLM fails or says no
                if "keyboard" in vlm_res.get('text', '').lower() or "shortcut" in vlm_res.get('text', '').lower():
                    score += 25
                    feedback_parts.append("Evidence screenshot likely correct (text match).")
                else:
                    score += 15 # Give credit for creating the file at least
                    feedback_parts.append("Evidence screenshot created but VLM check ambiguous.")
        except Exception as e:
            feedback_parts.append(f"Failed to analyze evidence screenshot: {e}")
            score += 5 # Minimal credit for file existing
        finally:
            if os.path.exists(temp_evidence.name):
                os.unlink(temp_evidence.name)
    else:
        feedback_parts.append("Evidence screenshot not created.")

    # 5. Trajectory Verification (30 pts)
    # Did they join the meeting 'TrainingSession'?
    # Did they act as 'Training Lead'?
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        traj_prompt = """
        Analyze these screenshots of a Jitsi Meet session.
        1. Did the user join a meeting (move past the welcome screen)?
        2. Is the user name 'Training Lead' visible anywhere?
        3. Is the meeting name 'TrainingSession' visible?
        
        Respond JSON: {"joined_meeting": bool, "name_visible": bool, "room_visible": bool}
        """
        
        traj_res = query_vlm(prompt=traj_prompt, images=frames)
        if traj_res.get('success'):
            parsed = traj_res.get('parsed', {})
            if parsed.get('joined_meeting'):
                score += 10
                feedback_parts.append("Joined meeting.")
            if parsed.get('name_visible'):
                score += 10
                feedback_parts.append("Correct display name used.")
            if parsed.get('room_visible'):
                score += 10
                feedback_parts.append("Correct room joined.")
        else:
            # Fallback points if VLM fails but app is running
            if result.get('app_running'):
                score += 15
                feedback_parts.append("App running (VLM trajectory check failed).")
    else:
        feedback_parts.append("No trajectory frames available.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }